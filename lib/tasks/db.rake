namespace :db do

  desc "Dumps the database to backups"
  task :dump => :environment do
      dump_fmt = 'c'      # or 'p', 't', 'd'
      dump_sfx = suffix_for_format dump_fmt
      backup_dir = backup_directory true

      FileUtils.rm_rf(Dir.glob("#{backup_dir}/#{Time.now.year}*"))

      pg_cmd = nil
      compress_cmd = nil
      file_name = ""
      with_config do |app, host, db, user|
          file_name = Time.now.strftime("%Y%m%d%H%M%S") + "_" + db + '.' + dump_sfx
          pg_cmd = "pg_dump -v -h #{host} -U #{user} #{db} > #{backup_dir}/#{file_name}"
          compress_cmd = "tar czf #{backup_dir}/#{file_name}.tar.gz #{backup_dir}/#{file_name}"
          # compress_cmd = "tar czf #{backup_dir}/#{file_name}.tar.gz --directory=#{backup_dir} #{file_name}"
      end
      puts pg_cmd
      exec "#{pg_cmd} && #{compress_cmd} && rm #{backup_dir}/#{file_name}"
      Conf.create(title: "BACKUP #{Time.now.to_i}", properties: {arquivo: "#{backup_dir}/#{file_name}.tar.gz"})
  end

  desc "Dumps the database to backups"
  task :custom_dump, [:filename, :with_versions] => :environment do |_,args|
      dump_fmt = 'c'      # or 'p', 't', 'd'
      dump_sfx = suffix_for_format dump_fmt
      backup_dir = backup_directory true

      FileUtils.rm_rf(Dir.glob("#{backup_dir}/psisp-dump-*"))

      pg_cmd = nil
      compress_cmd = nil
      file_name = ""
      compressed_file_name = nil
      with_config do |app, host, db, user, password|
          file_str = args[:filename].nil? ? "psisp-dump-#{Time.now.strftime("%Y%m%d%H%M%S")}_#{db}.#{dump_sfx}" : "psisp-dump-#{args[:filename]}.#{dump_sfx}"
          file_name = "#{backup_dir}/#{file_str}"
          
          pg_cmd = "export PGPASSWORD=\"#{ActiveRecord::Base.connection_db_config.configuration_hash[:password]}\"; pg_dump -v #{'--exclude-table versions' unless args[:with_versions] == true or args[:with_versions] == 'true'} -h #{host} -U #{user} #{db} > #{file_name}"
          
          compressed_file_name = "#{file_name}.tar.gz"
          compress_cmd = "tar czf #{compressed_file_name} #{file_name}"
          # compress_cmd = "tar czf #{backup_dir}/#{file_name}.tar.gz --directory=#{backup_dir} #{file_name}"
      end

      exec "#{pg_cmd} && #{compress_cmd} && rm #{file_name} && RAILS_ENV=#{Rails.env} bundle exec rake db:save_dump_file['#{compressed_file_name}']"
  end

  task :save_dump_file, [:filename] => :environment do |_,args|
    dump = Dump.create(title: "dump-#{Time.now.year}")
    dump.dump_file.attach(io: File.open(args.filename), filename: File.basename(args.filename), content_type: 'application/gzip')
  end

  desc "Dumps the database tables data"
  task :dump_data => :environment do
      tables = ActiveRecord::Base.connection.tables.map{|t| "-t public.#{t} "}.join
      dump_fmt = 'c'      # or 'p', 't', 'd'
      dump_sfx = suffix_for_format dump_fmt
      backup_dir = backup_directory true

      FileUtils.rm_rf(Dir.glob("#{backup_dir}/#{Time.now.year}*"))

      pg_cmd = nil
      compress_cmd = nil
      file_name = ""
      with_config do |app, host, db, user|
          file_name = Time.now.strftime("%Y%m%d%H%M%S") + "_" + db + '.' + dump_sfx
          pg_cmd = "pg_dump -v -h #{host} -U #{user} #{db} #{tables} > #{backup_dir}/#{file_name}"
          # compress_cmd = "tar czf #{backup_dir}/#{file_name}.tar.gz #{backup_dir}/#{file_name}"
          compress_cmd = "tar czf #{backup_dir}/#{file_name}.tar.gz --directory=#{backup_dir} #{file_name}"
      end
      puts pg_cmd
      exec "#{pg_cmd} && #{compress_cmd} && rm #{backup_dir}/#{file_name}"
  end

  desc "Dumps the database tables data"
  task :wipe_db => :environment do
      command = ActiveRecord::Base.connection.tables.map{|t| "drop table #{t} CASCADE; "}.join
      puts command
      ActiveRecord::Base.connection.execute(command)
  end

  desc "Show the existing database backups"
  task :list => :environment do
      backup_dir = backup_directory
      puts "#{backup_dir}"
      exec "/bin/ls -lt #{backup_dir}"
  end

  desc "Restores the database from a backup using PATTERN"
  task :restore, [:pat] => :environment do |task,args|
    if args.pat.present?
      cmd = nil
      with_config do |app, host, db, user|
          backup_dir = backup_directory
          files = Dir.glob("#{backup_dir}/*#{args.pat}*")
          case files.size
          when 0
            puts "No backups found for the pattern '#{args.pat}'"
          when 1
            file = files.first
            # fmt = format_for_file file
            # if fmt.nil?
            #   puts "No recognized dump file suffix: #{file}"
            # else
              cmd = "gunzip -c #{file} | psql -h #{host} -U #{user} #{db}"
              # cmd = "pg_restore -F #{fmt} -v -c -C #{file}"
            # end
          else
            puts "Too many files match the pattern '#{args.pat}':"
            puts ' ' + files.join("\n ")
            puts "Try a more specific pattern"
          end
      end
      unless cmd.nil?
        Rake::Task["db:wipe_db"].invoke
        # Rake::Task["db:create"].invoke
        puts cmd
        exec cmd
      end
    else
      puts 'Please pass a pattern to the task'
    end
  end

  desc "Restaura a tabela versions"
  task versions_recover: :environment do
    filename = "#{Rails.root}/db/migrate/#{Time.now.year+1}0205192411_create_versions.rb"
    unless ActiveRecord::Base.connection.data_source_exists? 'versions'
      File.open(filename, "w") do |f|
        code = <<-RUBY
class CreateVersions < ActiveRecord::Migration[5.2]
  TEXT_BYTES = 1_073_741_823

  def change
    create_table :versions do |t|
      t.string   :item_type, {:null=>false}
      t.integer  :item_id,   null: false, limit: 8
      t.string   :event,     null: false
      t.string   :whodunnit
      t.text     :object, limit: TEXT_BYTES

      t.datetime :created_at
    end
    add_index :versions, %i(item_type item_id)
  end
end
        RUBY

        f.write(code)
      end

      Rake::Task["db:migrate"].invoke
      FileUtils.rm(filename)
    else
      puts "Tabela versions já existe."
    end
  end
    
  desc "Verifica se existem dados para serem ajustados"
  task data: :environment do
    PaperTrail.admin_did_it
    migrations = Dir.glob("#{Rails.root}/db/data/migrate/*").map{|d| d.scan(/\d/).join('').to_i}.sort{|a,b| a<=>b}.reject{|d| DataMigrate.where(code: d).any?}
    if migrations.any?
    migrations.each do |m|
      begin
        mod = Migrate.all_the_modules.select{|mod| mod.name.include?(m.to_s)}[0]
        mod.update
      rescue Exception => e
        puts "\n\n HOUVE UMA FALHA NA MIGRAÇÃO DE DADOS #{m}"
        Conf.create(title: "FALHA na Data migrate: #{m.to_s}", properties: {error: e.message, backtrace: e.backtrace})
      else
        puts "Migração de dados #{m} bem sucedida!"
        if DataMigrate.create(code: m.to_s)
          Conf.create(title: "Data migrate: #{m.to_s}", properties: {message: "Migração de dados #{m} bem sucedida!"})
        end
      end
    end
    else
      puts "Sem migrações de dados pendentes."
      
    end
  end

  private

  def suffix_for_format suffix
      case suffix
      when 'c' then 'dump'
      when 'p' then 'sql'
      when 't' then 'tar'
      when 'd' then 'dir'
      else nil
      end
  end

  def format_for_file file
      case file
      when /\.dump$/ then 'c'
      when /\.sql$/  then 'p'
      when /\.dir$/  then 'd'
      when /\.tar$/  then 't'
      else nil
      end
  end

  def backup_directory create=false
      backup_dir = "#{Rails.root}/db/backups"
      if create and not Dir.exist?(backup_dir)
        puts "Creating #{backup_dir} .."
        FileUtils.mkdir_p(backup_dir)
      end
      backup_dir
  end

  def with_config
      yield 'Agencies'.underscore,
            ActiveRecord::Base.connection_db_config.configuration_hash[:host],
            ActiveRecord::Base.connection_db_config.configuration_hash[:database],
            ActiveRecord::Base.connection_db_config.configuration_hash[:username]
  end
end