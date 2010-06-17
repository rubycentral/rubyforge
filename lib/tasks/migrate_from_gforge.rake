require 'active_record'

namespace :redmine do

  task :migrate_from_gforge => [:environment, 'db:migrate:reset', 'redmine:load_default_data'] do 
    include GForgeMigrate
    Project.reset_column_information
    Project.transaction do 
      puts "Migrating groups to projects"
      count = GForgeGroup.non_system.active.count
      GForgeGroup.non_system.active.each_with_index do |gforge_group, idx|
        puts "Creating Project from Group #{gforge_group.unix_group_name} (group_id #{gforge_group.group_id}) (#{idx+1} of #{count})"
        if Project.exists?(:name => gforge_group.group_name[0..29])
          puts "Working around '#{gforge_group.group_name}'; that's the same name as an existing project"
          gforge_group.group_name = gforge_group.group_name[0..20] + gforge_group.group_id.to_s
          puts "Set gforge_group.group_name to #{gforge_group.group_name}"
        end
        Project.create!(:name => gforge_group.group_name[0..29], :created_on => Time.at(gforge_group.register_time), :homepage => (gforge_group.homepage[0..254] rescue ""), :identifier => gforge_group.unix_group_name)
        gforge_group.user_group.each do |user_group|
          # create User if not exists
          # create Member
          # what's a Principal?  An admin?
        end
        break
      end
    end
  end

end

module GForgeMigrate
  class GForgeTable < ActiveRecord::Base
    GForgeTable.establish_connection(:adapter => "postgresql", :username => (ENV["GFORGE_USERNAME"] || "gforge"), :password => ENV["GFORGE_PASSWORD"], :database => (ENV["GFORGE_DATABASE_NAME"] || "gforge"), :host => "localhost")
  end
  class GForgeGroup < GForgeTable
    set_table_name 'groups'
    set_primary_key 'group_id'
    has_many :user_group, :class_name => 'GForgeUserGroup', :foreign_key => 'group_id'
    has_many :users, :through => :user_group
    named_scope :active, :conditions => {:status => 'A'}
    named_scope :non_system, :conditions => 'group_id > 4'
  end 
  class GForgeUserGroup < GForgeTable
    set_table_name "user_group"
    set_primary_key 'user_group_id'
    belongs_to :user, :class_name => "GForgeUser", :foreign_key => 'user_id'
    belongs_to :group, :class_name => 'GForgeGroup'
  end
  class GForgeUser < GForgeTable
    set_table_name 'users'
    set_primary_key "user_id"
    has_many :user_group, :class_name => 'GForgeUserGroup', :foreign_key => 'user_id'
    has_many :artifacts, :foreign_key => 'submitted_by'
    has_many :groups, :through => :user_group
    belongs_to :supported_language, :foreign_key => 'language'
    belongs_to :user_type, :foreign_key => 'type_id'
    has_many :forum_messages, :class_name => "Forum", :foreign_key => "posted_by"
    has_many :news_bytes, :foreign_key => "submitted_by"
    named_scope :active, :conditions => {:status => "A"}
  end
end
# include GForgeMigrate
# GForgeGroup.first.user_group.first.user
