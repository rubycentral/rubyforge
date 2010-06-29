module GForgeMigrate

  class GForgeTable < ActiveRecord::Base
    GForgeTable.establish_connection(:adapter => "postgresql", :username => (ENV["GFORGE_USERNAME"] || "gforge"), :password => ENV["GFORGE_PASSWORD"], :database => (ENV["GFORGE_DATABASE_NAME"] || "gforge"), :host => "localhost")
  end

  class GForgeGroup < GForgeTable
    set_table_name 'groups'
    set_primary_key 'group_id'
    has_many :user_group, :class_name => 'GForgeUserGroup', :foreign_key => 'group_id'
    has_many :users, :through => :user_group
    has_many :artifact_group_lists, :class_name => "GForgeArtifactGroupList", :foreign_key => 'group_id'
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
    def convert_to_redmine_user
      puts "Converting GForge user #{id} to a Redmine user"
      user = User.new(:mail => email, :created_on => Time.at(add_date))
      user.firstname = sanitized_name(firstname)
      user.lastname = sanitized_name(lastname)
      user.type = "User"
      user.hashed_password = user_pw
      user.language = supported_language.language_code if language
      if User.exists?(:login => user_name)
        user.login = "#{user_name}_#{id}"
      else
        user.login = user_name
      end
      user.save!
      # TODO GForge records time zone in users.timezone in the format "US/Eastern"
      # Redmine has it in user_preferences.time_zone in the format "Eastern Time (US & Canada)"
      user.preference = UserPreference.create!(:user => user, :hide_mail => true, :time_zone => timezone, :others => {:public_keys => authorized_keys})
      user
    end
    private
    def sanitized_name(str)
      if str.blank? || str.gsub(/[^a-z0-9A-Z\s]/, "").blank?
        "None"
      else
        str.gsub(/[^a-z0-9A-Z\s]/, "")[0..29]
      end
    end
  end

  class GForgeSupportedLanguage < GForgeTable
    set_primary_key 'language_id'
    set_table_name 'supported_languages'
  end

  class GForgeArtifactGroupList < GForgeTable
    set_primary_key 'group_artifact_id'
    set_table_name 'artifact_group_list'
    belongs_to :group, :class_name => 'GForgeGroup', :foreign_key => 'group_id'
    has_many :artifacts, :class_name => "GForgeArtifact", :foreign_key => 'group_artifact_id'
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
    belongs_to :artifact_group_list, :class_name => "GForgeArtifactGroupList", :foreign_key => 'group_artifact_id'
    belongs_to :submitted_by, :class_name => 'GForgeUser', :foreign_key => 'submitted_by'
    belongs_to :category, :class_name => "GForgeArtifactCategory", :foreign_key => 'category_id'
    def convert_to_redmine_issue_in(project)
      Issue.create!(
        :project => project, 
        :tracker => Tracker.find_by_name(artifact_group_list.corresponding_redmine_tracker_name), 
        :author => create_or_fetch_user(submitted_by),
        :description => details,
        :status => redmine_status,
        :subject => summary[0..254])
        # FIXME map issue category, etc
    end
    # For GForge, this is: (1) Open, (2) Closed, (3) Deleted.
    def redmine_status
      if status_id == 1
        IssueStatus.find_by_name("New")
      elsif status_id == 2
        IssueStatus.find_by_name("Closed")
      else
        IssueStatus.find_by_name("Deleted")
      end
    end
  end
  
  class GForgeArtifactCategory < GForgeTable
    set_table_name 'artifact_category'
    belongs_to :auto_assign_to, :class_name => 'GForgeUser', :foreign_key => 'auto_assign_to'
  end
  
  def create_or_fetch_user(gforge_user)
    if user = User.find_by_mail(gforge_user.email) 
      user
    else
      gforge_user.convert_to_redmine_user
    end
  end
  
end

