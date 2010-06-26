
module GForgeMigrate
  class GForgeTable < ActiveRecord::Base
    GForgeTable.establish_connection(:adapter => "postgresql", :username => (ENV["GFORGE_USERNAME"] || "gforge"), :password => ENV["GFORGE_PASSWORD"], :database => (ENV["GFORGE_DATABASE_NAME"] || "gforge"), :host => "localhost")
  end
  class GForgeGroup < GForgeTable
    set_table_name 'groups'
    set_primary_key 'group_id'
    has_many :user_group, :class_name => 'GForgeUserGroup', :foreign_key => 'group_id'
    has_many :users, :through => :user_group
    has_many :artifact_groups, :class_name => "GForgeArtifactGroup", :foreign_key => 'group_id'
    named_scope :active, :conditions => {:status => 'A'}
    named_scope :non_system, :conditions => 'group_id > 4'
  end 
  class GForgeUserGroup < GForgeTable
    set_table_name "user_group"
    set_primary_key 'user_group_id'
    belongs_to :user, :class_name => "GForgeUser", :foreign_key => 'user_id'
    belongs_to :group, :class_name => 'GForgeGroup'
    def group_admin?
      admin_flags.strip == 'A'
    end
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
  class GForgeArtifactGroup < GForgeTable
    set_primary_key 'group_artifact_id'
    set_table_name 'artifact_group_list'
    belongs_to :group, :class_name => 'GForgeGroup', :foreign_key => 'group_id'
    has_many :artifacts, :class_name => "GForgeArtifact", :foreign_key => 'artifact_group_id'
    def corresponding_redmine_tracker_name
      case name
        when "Feature Requests": "Feature"
        when "Bugs": "Bug"
        when "Support Requests": "Support"
        when "Patches": "Patch"
        else "Bug"
      end
    end
  end
  class GForgeArtifact < GForgeTable
    set_table_name 'artifact'
    set_primary_key 'artifact_id'
    belongs_to :artifact_group, :class_name => "GForgeArtifactGroup", :foreign_key => 'artifact_group_id'
    belongs_to :submitted_by, :class_name => 'GForgeUser', :foreign_key => 'submitted_by'
  end
  
end

