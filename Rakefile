$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)

require 'bundler/gem_tasks'

Dir.glob(File.expand_path('../tasks/*.rake', __FILE__)).each do |task|
  load task
end

desc "Bump version to the next patch level"
task :bump do
  path = 'lib/bipbip/version.rb'
  version_file = File.read(path)
  begin
    patch_level = version_file.match(/VERSION = '\d+\.\d+\.(\d*)'/)[1].to_i
  rescue
    abort('Unreadable format in version string')
  end
  version_file = version_file.gsub(/(VERSION = '\d+\.\d+\.)(\d+)/, '\1'+"#{patch_level + 1}")
  File.open(path, "w") {|file| file.puts version_file}
  sh "git add #{path}"
  sh 'git commit -m "Bump version"'
end