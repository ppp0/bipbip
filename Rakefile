$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)

require 'bundler/gem_tasks'

Dir.glob(File.expand_path('../tasks/*.rake', __FILE__)).each do |task|
  load task
end

desc "Bump version to the next patch level"
task :bump do
  version_file = 'lib/bipbip/version.rb'
  file_content = File.read(version_file)
  begin
    patch_level = file_content.match(/VERSION = '\d+\.\d+\.(\d*)'/)[1].to_i
  rescue
    abort('Unreadable format in version string')
  end
  file_content = file_content.gsub(/(VERSION = '\d+\.\d+\.)(\d+)/, '\1'+"#{patch_level + 1}")
  File.open(version_file, "w") {|file| file.puts file_content}
  sh "git add #{version_file}"
  sh 'git commit -m "Bump version"'
end