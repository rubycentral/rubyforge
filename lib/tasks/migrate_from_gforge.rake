require 'active_record'

namespace :redmine do

  task :create_anonymous_user => :environment do
    user = AnonymousUser.new(:firstname => "Anonymous", :lastname => "User", :mail => "anonymous@example.org", :type => "AnonymousUser")
    user.login = "anonymous"
    user.save!
  end
  
  task :migrate_from_gforge => [:environment, 'db:migrate:reset', 'redmine:load_default_data', 'redmine:create_anonymous_user'] do 
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
          user = create_or_fetch_user(user_group.user)
          # create Member
          # what's a Principal?  An admin?
        end
        break
      end
    end
  end
  
  def create_or_fetch_user(gforge_user)
    if user = User.find_by_mail(gforge_user.email) 
      user
    else
      user = User.new(
      :mail => gforge_user.email, 
      :hashed_password => gforge_user.user_pw, 
      :firstname => (gforge_user.realname.split(" ")[0] rescue gforge_user.realname), 
      :lastname => (gforge_user.realname.split(" ")[1] rescue ""),
      :created_on => Time.at(gforge_user.add_date),
      :type => "User"
      )
      user.language = gforge_user.supported_language.language_code if gforge_user.language
      user.login = gforge_user.user_name
      user.save!
      # TODO GForge records time zone in users.timezone in the format "US/Eastern"
      # Redmine has it in user_preferences.time_zone in the format "Eastern Time (US & Canada)"
      user.preference = UserPreference.create!(:user => user, :hide_mail => true, :time_zone => gforge_user.timezone, :others => {:public_keys => gforge_user.authorized_keys})
      user
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
    belongs_to :supported_language, :foreign_key => 'language', :class_name => "GForgeSupportedLanguage"
    belongs_to :user_type, :foreign_key => 'type_id'
    has_many :forum_messages, :class_name => "Forum", :foreign_key => "posted_by"
    has_many :news_bytes, :foreign_key => "submitted_by"
    named_scope :active, :conditions => {:status => "A"}
  end
  class GForgeSupportedLanguage < GForgeTable
    set_primary_key 'language_id'
    set_table_name 'supported_languages'
  end
  
end
# include GForgeMigrate
# GForgeGroup.first.user_group.first.user
