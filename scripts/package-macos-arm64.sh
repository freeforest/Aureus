#!/bin/bash
# MIT; see the source snapshot's LICENSE. No build, launch, download or publish.
set -euo pipefail
if [[ $# -ne 3 ]]; then
  printf '%s\n' 'Usage: bash package-macos-arm64.sh VERIFIED_RELEASE_APP CLEAN_SOURCE_SNAPSHOT NEW_OUTPUT_DIRECTORY' >&2
  exit 64
fi
exec /usr/bin/ruby - "$@" <<'RUBY'
require 'json'
require 'digest'
require 'pathname'
require 'fileutils'
require 'time'

$stdout.sync = true

app, source, output = ARGV
DENIED = %w[.git .secrets xcuserdata DerivedData default.profraw].freeze
CHART = 'Aureus/Resources/ThirdParty/LightweightCharts/5.2.0'.freeze
ROOT_FILES = %w[.gitignore LICENSE README.md THIRD_PARTY_NOTICES.md scripts/package-macos-arm64.sh
  Aureus.xcodeproj/project.pbxproj Aureus.xcodeproj/xcshareddata/xcschemes/Aureus.xcscheme
  Aureus.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  Aureus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved].freeze

def check_path(path, kind)
  raise 'absolute normalized path required' unless path.start_with?('/') && Pathname.new(path).cleanpath.to_s == path
  current = Pathname.new('/')
  Pathname.new(path).each_filename do |part|
    raise 'denied path component' if DENIED.include?(part)
    current = current.join(part)
    stat = File.lstat(current)
    raise "symlink in explicit path: #{current}" if stat.symlink?
    final = current.to_s == path
    raise "wrong path type: #{current}" unless final && kind == :file ? stat.file? : stat.directory?
  end
end

def within?(child, parent)
  child == parent || child.start_with?(parent + '/')
end

def validate_internal_link(root, rel)
  pending = rel.split('/')
  current = root
  traversals = 0
  until pending.empty?
    part = pending.shift
    candidate = current + '/' + part
    stat = File.lstat(candidate)
    if stat.symlink?
      traversals += 1
      raise 'symlink cycle or excessive depth' if traversals > 32
      target = File.expand_path(File.readlink(candidate), current)
      raise "external link: #{rel}" unless within?(target,root)
      suffix = target == root ? [] : target[(root.length+1)..-1].split('/')
      pending = suffix + pending
      current = root
    else
      raise 'nonordinary link target' unless stat.file? || stat.directory?
      current = candidate
    end
  end
end

def walk(root, links: false)
  rows = []
  visit = lambda do |rel|
    path = rel.empty? ? root : File.join(root, rel)
    stat = File.lstat(path)
    row = {'path'=>rel.empty? ? '.' : rel, 'mode'=>sprintf('%04o', stat.mode & 07777)}
    if stat.symlink?
      raise "link not allowed: #{rel}" unless links
      target = File.readlink(path)
      validate_internal_link(root,rel)
      row.merge!('type'=>'symlink', 'target'=>target)
    elsif stat.directory?
      row['type'] = 'directory'
      rows << row
      Dir.children(path).sort_by(&:b).each do |name|
        raise 'denied directory entry' if DENIED.include?(name) || name.include?("\n") || name.include?("\r")
        visit.call(rel.empty? ? name : rel + '/' + name)
      end
      return
    elsif stat.file?
      row.merge!('type'=>'file', 'size'=>stat.size, 'sha256'=>Digest::SHA256.file(path).hexdigest)
    else
      raise "nonordinary file: #{rel}"
    end
    rows << row
  end
  visit.call('')
  rows.sort_by { |row| row['path'].b }
end

def snapshot_allowed?(rel)
  ROOT_FILES.include?(rel) ||
    (rel.match?(%r{\A(?:Aureus|AureusTests|AureusUITests)/.+\.(?:swift|entitlements)\z})) ||
    %w[LICENSE NOTICE PROVENANCE.md aureus-market-chart.js lightweight-charts.standalone.production.js market-chart.html].any? { |n| rel == CHART + '/' + n }
end

# Enumerate and validate every source path before reading file bytes.
def snapshot_files(root)
  files = []
  visit = lambda do |rel|
    path = rel.empty? ? root : root + '/' + rel
    stat = File.lstat(path)
    raise "source symlink: #{rel}" if stat.symlink?
    if stat.directory?
      Dir.children(path).sort_by(&:b).each do |name|
        raise 'denied source component' if DENIED.include?(name) || name.include?("\n") || name.include?("\r")
        visit.call(rel.empty? ? name : rel + '/' + name)
      end
    else
      raise "unapproved source path: #{rel}" unless stat.file? && snapshot_allowed?(rel)
      files << rel
    end
  end
  visit.call('')
  raise 'incomplete clean snapshot' unless (ROOT_FILES - files).empty?
  files.sort_by(&:b).map do |rel|
    path = root + '/' + rel
    {'path'=>rel, 'size'=>File.size(path), 'mode'=>sprintf('%04o', File.stat(path).mode & 07777), 'sha256'=>Digest::SHA256.file(path).hexdigest}
  end
end

check_path(app, :directory)
check_path(source, :directory)
raise 'Aureus.app required' unless File.basename(app) == 'Aureus.app'
raise 'output must be new and absolute' unless output.start_with?('/') && Pathname.new(output).cleanpath.to_s == output && !File.exist?(output) && !File.symlink?(output)
check_path(File.dirname(output), :directory)
raise 'input/output overlap' if [app, source].any? { |p| within?(output,p) || within?(p,output) } || within?(app,source) || within?(source,app)
source_before = snapshot_files(source)
app_before = walk(app, links: true)
Dir.mkdir(output, 0700)
%w[Audit Staging Artifacts Mount InstallCheck Extracted].each { |n| Dir.mkdir(output + '/' + n, 0700) }
audit = output + '/Audit'

def save_new(path, text)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(text); f.flush; f.fsync }
end
def save_json(path, value)
  save_new(path, JSON.pretty_generate(value) + "\n")
end

sequence = 0
run = lambda do |label, argv, cwd = output|
  sequence += 1
  prefix = audit + '/' + format('%03d-%s', sequence, label)
  record = {argv:argv, cwd:cwd, wrapper_pid:Process.pid, start_utc:Time.now.utc.iso8601(6), stdout:prefix+'.stdout.log', stderr:prefix+'.stderr.log'}
  save_json(prefix+'.start.json', record)
  File.open(record[:stdout], File::WRONLY | File::CREAT | File::EXCL, 0600) do |out|
    File.open(record[:stderr], File::WRONLY | File::CREAT | File::EXCL, 0600) do |err|
      pid = Process.spawn(*argv, chdir:cwd, out:out, err:err)
      record[:child_pid] = pid
      save_json(prefix+'.launched.json', record)
      _, status = Process.waitpid2(pid)
      out.flush; out.fsync; err.flush; err.fsync
      record.merge!(end_utc:Time.now.utc.iso8601(6), underlying_exit:status.exitstatus, signal:status.termsig, success:status.success?, waited:true)
    end
  end
  save_json(prefix+'.end.json', record)
  puts "#{label}: exit=#{record[:underlying_exit]} signal=#{record[:signal].inspect}"
  raise "command failed: #{label}; see #{prefix}.end.json" unless record[:success]
  [File.binread(record[:stdout]), File.binread(record[:stderr]), record]
end

plist = lambda do |label, path|
  JSON.parse(run.call(label, ['/usr/bin/plutil','-convert','json','-o','-',path])[0])
end
inspect_app = lambda do |label, root|
  manifest = walk(root, links:true)
  forbidden = manifest.select { |r| r['path'].match?(/(?:\.xctest|\.dSYM|XCTest|XCTAutomation|Testing\.framework|libTesting|\.swiftmodule|\.profraw|\.sqlite(?:-|\z)|\.xcresult|\.DS_Store)/i) }
  raise "development/private artifact in #{label}" unless forbidden.empty?
  info = plist.call(label+'Info', root+'/Contents/Info.plist')
  expected = {'CFBundleIdentifier'=>'com.aureus.wealthterminal','CFBundleShortVersionString'=>'0.1','CFBundleVersion'=>'1','LSMinimumSystemVersion'=>'14.0','CFBundleExecutable'=>'Aureus'}
  raise "unexpected App identity: #{label}" unless expected.all? { |k,v| info[k] == v }
  macho = manifest.select do |r|
    next false unless r['type'] == 'file'
    magic = File.open(root+'/'+r['path'],'rb') { |f| f.read(4) }
    ["\xCF\xFA\xED\xFE", "\xCE\xFA\xED\xFE", "\xFE\xED\xFA\xCF", "\xFE\xED\xFA\xCE", "\xCA\xFE\xBA\xBE", "\xBE\xBA\xFE\xCA", "\xCA\xFE\xBA\xBF", "\xBF\xBA\xFE\xCA"].map(&:b).include?(magic)
  end
  raise 'missing main Mach-O' unless macho.any? { |r| r['path'] == 'Contents/MacOS/Aureus' }
  architectures = macho.each_with_index.map do |r,i|
    binary = root+'/'+r['path']
    desc = run.call(label+"File#{i}", ['/usr/bin/file',binary])[0].strip
    arch = run.call(label+"Arch#{i}", ['/usr/bin/lipo','-archs',binary])[0].strip
    raise "not arm64-only: #{r['path']}" unless arch == 'arm64'
    {'path'=>r['path'],'architectures'=>arch,'file'=>desc,'sha256'=>r['sha256']}
  end
  result = {root:root,info:info,manifest:manifest,macho:architectures}
  save_json(audit+'/'+label+'Identity.json',result)
  result
end

mounted = false
mountpoint = output + '/Mount'
begin
  save_json(audit+'/Inputs.json',{utc:Time.now.utc.iso8601(6),app:app,source:source,source_files:source_before,release_app:app_before})
  release = inspect_app.call('Release', app)
  entitlements = source+'/Aureus/Aureus.entitlements'
  entitlement_value = plist.call('SourceEntitlements',entitlements)
  expected_entitlements = {'com.apple.security.app-sandbox'=>true,'com.apple.security.files.user-selected.read-write'=>true,'com.apple.security.network.client'=>true}
  raise 'unexpected source entitlements' unless entitlement_value == expected_entitlements
  staged_app = output+'/Staging/Aureus.app'
  run.call('StageApp',['/usr/bin/ditto',app,staged_app])
  raise 'copy did not preserve full App' unless walk(staged_app,links:true) == app_before
  resources = staged_app+'/Contents/Resources'
  chart_source = source+'/'+CHART
  chart_dest = resources+'/ThirdParty/LightweightCharts/5.2.0'
  %w[LICENSE NOTICE PROVENANCE.md aureus-market-chart.js lightweight-charts.standalone.production.js market-chart.html].each do |n|
    check_path(chart_dest+'/'+n,:file)
    raise "chart resource mismatch: #{n}" unless Digest::SHA256.file(chart_source+'/'+n).hexdigest == Digest::SHA256.file(chart_dest+'/'+n).hexdigest
  end
  privacy = app_before.select { |r| r['type']=='file' && r['path'].include?('GRDB') && File.basename(r['path'])=='PrivacyInfo.xcprivacy' }
  raise 'GRDB privacy resource missing' if privacy.empty?
  licenses = resources+'/Licenses'
  raise 'license destination already exists' if File.exist?(licenses)
  Dir.mkdir(licenses,0755)
  FileUtils.copy_file(source+'/LICENSE',licenses+'/LICENSE',true)
  notices = File.read(source+'/THIRD_PARTY_NOTICES.md')
  grdb = notices.match(/<!-- BEGIN GRDB LICENSE -->\n(.*?)\n<!-- END GRDB LICENSE -->/m)
  raise 'complete GRDB notice missing' unless grdb
  save_new(licenses+'/GRDB-LICENSE',grdb[1]+"\n")
  {'LICENSE'=>'Charts-LICENSE','NOTICE'=>'Charts-NOTICE','PROVENANCE.md'=>'Charts-PROVENANCE.md'}.each do |original, name|
    FileUtils.copy_file(chart_source+'/'+original,licenses+'/'+name,true)
    notices = notices.gsub('('+CHART+'/'+original+')','('+name+')')
  end
  save_new(licenses+'/THIRD_PARTY_NOTICES.md',notices)
  # Readable public notices; no executable or entitlement change here.
  %w[GRDB-LICENSE THIRD_PARTY_NOTICES.md].each { |n| File.chmod(0644,licenses+'/'+n) }
  pre_sign = walk(staged_app,links:true)
  original_paths = app_before.to_h { |r| [r['path'],r] }
  raise 'business resource changed before signing' unless pre_sign.all? { |r| !original_paths.key?(r['path']) || original_paths[r['path']] == r }
  save_json(audit+'/BeforeSigning.json',{manifest:pre_sign,allowed_addition:'Contents/Resources/Licenses only',grdb_privacy:privacy})
  nested_files = release[:macho].map { |r| r['path'] }.reject { |p| p=='Contents/MacOS/Aureus' }.sort_by { |p| [-p.count('/'),p.b] }
  nested_bundles = pre_sign.select { |r| r['type']=='directory' && r['path'].match?(/\.(?:app|xpc|framework|bundle)\z/) && nested_files.any? { |p| p.start_with?(r['path']+'/') } }.map { |r| r['path'] }.sort_by { |p| [-p.count('/'),p.b] }
  save_json(audit+'/SigningPlan.json',{identity:'-',timestamp:'none',nested_files:nested_files,nested_bundles:nested_bundles,app_last:staged_app,entitlements_sha256:Digest::SHA256.file(entitlements).hexdigest})
  nested_files.each_with_index { |rel,i| run.call("SignCode#{i}",['/usr/bin/codesign','--force','--sign','-','--timestamp=none',staged_app+'/'+rel]) }
  nested_bundles.each_with_index { |rel,i| run.call("SignBundle#{i}",['/usr/bin/codesign','--force','--sign','-','--timestamp=none',staged_app+'/'+rel]) }
  run.call('SignApp',['/usr/bin/codesign','--force','--sign','-','--timestamp=none','--entitlements',entitlements,staged_app])
  run.call('VerifyStaged',['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',staged_app])
  display = run.call('Signature',['/usr/bin/codesign','--display','--verbose=4',staged_app])
  raise 'not ad-hoc' unless display[1].include?('Signature=adhoc') && !display[1].include?('Authority=Developer ID')
  signed_ent = run.call('Entitlements',['/usr/bin/codesign','--display','--entitlements',':-',staged_app])
  actual_ent = plist.call('ActualEntitlements',signed_ent[2][:stdout])
  raise 'actual entitlements differ' unless actual_ent == expected_entitlements
  staged = inspect_app.call('Staged',staged_app)
  frozen_app = staged[:manifest]
  save_json(audit+'/SignedIdentity.json',{signature:display[1],entitlements:actual_ent,manifest:frozen_app,macho:staged[:macho]})

  guide = File.read(source+'/README.md')
  install = guide.split("## Install the candidate\n",2)[1]&.split("## Build from source\n",2)&.first
  raise 'public install section missing' unless install
  save_new(output+'/Staging/INSTALL.md',"# Aureus 0.1 candidate — installation\n"+install+"\nLicenses are supplied in Licenses/ and in Aureus.app/Contents/Resources/Licenses.\n")
  File.chmod(0644,output+'/Staging/INSTALL.md')
  run.call('CopyImageLicenses',['/usr/bin/ditto',licenses,output+'/Staging/Licenses'])
  File.symlink('/Applications',output+'/Staging/Applications')
  artifacts = output+'/Artifacts'
  dmg = artifacts+'/Aureus-0.1-candidate-macos-arm64.dmg'
  zip = artifacts+'/Aureus-0.1-candidate-source.zip'
  run.call('CreateDMG',['/usr/bin/hdiutil','create','-volname','Aureus 0.1 Candidate','-srcfolder',output+'/Staging','-fs','HFS+','-format','UDZO','-nospotlight',dmg])
  run.call('VerifyDMG',['/usr/bin/hdiutil','verify',dmg])
  attached = run.call('AttachDMG',['/usr/bin/hdiutil','attach','-readonly','-nobrowse','-noautoopen','-mountpoint',mountpoint,'-plist',dmg])
  mounted = true
  attach_info = plist.call('MountedDevices',attached[2][:stdout])
  mounts = attach_info.fetch('system-entities').map { |entity| entity['mount-point'] }.compact
  raise 'unexpected mount target' unless mounts == [mountpoint]
  entries = Dir.children(mountpoint).sort_by(&:b)
  expected_entries = %w[Applications Aureus.app INSTALL.md Licenses]
  raise 'unexpected image entries' unless (expected_entries-entries).empty? && (entries-expected_entries-%w[.fseventsd .Trashes .DS_Store]).empty?
  raise 'wrong Applications shortcut' unless File.symlink?(mountpoint+'/Applications') && File.readlink(mountpoint+'/Applications')=='/Applications'
  raise 'mounted guide changed' unless Digest::SHA256.file(mountpoint+'/INSTALL.md').hexdigest == Digest::SHA256.file(output+'/Staging/INSTALL.md').hexdigest
  raise 'mounted licenses changed' unless walk(mountpoint+'/Licenses') == walk(output+'/Staging/Licenses')
  mounted_app = walk(mountpoint+'/Aureus.app',links:true)
  raise 'mounted App changed' unless mounted_app == frozen_app
  installed = output+'/InstallCheck/Aureus.app'
  run.call('CopyInstallCheck',['/usr/bin/ditto',mountpoint+'/Aureus.app',installed])
  raise 'install copy changed' unless walk(installed,links:true) == frozen_app
  run.call('VerifyInstallCopy',['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',installed])
  copied = inspect_app.call('InstallCopy',installed)
  save_json(audit+'/ImageVerification.json',{utc:Time.now.utc.iso8601(6),entries:entries,devices:attach_info,staging_equals_mounted_equals_copy:true,mounted_manifest:mounted_app,copied_manifest:copied[:manifest],app_launched:false})
  run.call('DetachDMG',['/usr/bin/hdiutil','detach',mountpoint])
  mounted = false
  raise 'mount point not empty after detach' unless Dir.children(mountpoint).empty?

  # Explicit files only: no recursive ZIP of a working directory or metadata.
  paths = source_before.map { |r| r['path'] }
  run.call('CreateSourceZIP',['/usr/bin/zip','-X','-q',zip,*paths],source)
  listed = run.call('ListSourceZIP',['/usr/bin/unzip','-Z1',zip])[0].lines.map(&:chomp)
  raise 'ZIP entries differ from approved snapshot' unless listed.sort_by(&:b) == paths && listed.uniq.size == listed.size
  run.call('ExtractSourceZIP',['/usr/bin/unzip','-q',zip,'-d',output+'/Extracted'])
  extracted = snapshot_files(output+'/Extracted')
  raise 'extracted ZIP bytes/modes differ' unless extracted == source_before
  raise 'snapshot changed during packaging' unless snapshot_files(source) == source_before
  raise 'Release output changed during packaging' unless walk(app,links:true) == app_before
  raise 'signed staging changed' unless walk(staged_app,links:true) == frozen_app
  save_json(audit+'/SourceArchiveVerification.json',{entries:listed,extracted:extracted,source_unchanged:true,release_unchanged:true,staging_unchanged:true})
  archives = [dmg,zip].map { |p| {file:File.basename(p),size:File.size(p),sha256:Digest::SHA256.file(p).hexdigest} }
  save_new(artifacts+'/SHA256SUMS',archives.map { |r| r[:sha256]+'  '+r[:file]+"\n" }.join)
  File.chmod(0644,artifacts+'/SHA256SUMS')
  save_json(audit+'/PackageResult.json',{outcome:'CANDIDATES VERIFIED — Awaiting Reviewer Gate',utc:Time.now.utc.iso8601(6),archives:archives,commands:sequence,mounted:false,app_launched:false,release_build_performed_by_script:false})
  puts JSON.pretty_generate(archives)
rescue => error
  save_json(audit+'/PackageFailure.json',{utc:Time.now.utc.iso8601(6),error:error.message,mounted:mounted,mountpoint:mountpoint,commands:sequence,retry_performed:false})
  warn error.message
  warn "No cleanup or retry performed. Mount state: #{mounted}; #{mountpoint}"
  exit 1
end
RUBY
