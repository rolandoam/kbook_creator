CURL = "/usr/bin/curl"
BRANCH = "develop"

file ".creator.rb" do
  curl("creator.rb", ".creator.rb")
end

task :default => [:create]

desc "Creates the e-book"
task :create => [:html] do
end

desc "Creates the html from the sources and media"
task :html => [".creator.rb", :prepare] do
  require ".creator.rb"
  
  # get the latest version of media
  curl("media/main.css")
  MOBI.new.create(ENV['PWD'])
end

desc "Cleans the output"
task :clean do
  rm_rf "out"
end

desc "Prepares the current directory and creates the tree structure"
task :prepare => [".creator.rb"] do
  mkdir_p "source"
  mkdir_p "media"
  mkdir_p "out"

  if !File.exists?("config.yaml") || ask_yn("replace config.yaml with default version?")
    rm_f "config.yaml"
    curl("config.yaml")
  end
end

desc "Updates the current version of the creator"
task :update do
  rm_f ".creator.rb"
  Rake::Task["prepare"].invoke
end

def curl(file, dest = nil, base_path = "http://github.com/funkaster/kbook_creator/raw", branch = BRANCH)
  sh "#{CURL} -s -o '#{dest ? dest : file}' '#{base_path}/#{branch}/#{file}'"
end

# ask yes/no question
def ask_yn(msg)
  print "#{msg} (y/N): "
  answer = $stdin.gets.chomp.downcase
  
  answer[0,1] == "y"
end
