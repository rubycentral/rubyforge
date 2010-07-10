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
    has_many :forum_groups, :class_name => "GForgeForumGroup", :foreign_key => 'group_id'
    has_many :document_groups, :class_name => "GForgeDocumentGroup", :foreign_key => 'group_id'
    named_scope :active, :conditions => {:status => 'A'}
    named_scope :non_system, :conditions => 'group_id > 4'
    def redmine_status
      if status == 'A'
        Project::STATUS_ACTIVE
      else
        Project::STATUS_ARCHIVED
      end
    end
    # TODO - how about these fields?  use_blah (use_survey, use_forum, etc), license_other, license
  end 
  
  class GForgeForumGroup < GForgeTable
    set_table_name "forum_group_list"
    set_primary_key "group_forum_id"
    belongs_to :group, :class_name => "GForgeGroup"
    has_many :forum_messages, :class_name => "GForgeForumMessage", :foreign_key => "group_forum_id"
    named_scope :active, :conditions => "is_public != 9"
    def convert_to_redmine_board_in(project)
      # I don't see an equivalent to allow_anonymous, is_public, or send_all_posts_to
      project.boards.create!(:name => forum_name, :description => (description.blank? ? "None" : description))
    end
  end
  
  class GForgeForumMessage < GForgeTable
    set_table_name "forum"
    set_primary_key "msg_id"
    belongs_to :forum_group, :class_name => 'GForgeForumGroup', :foreign_key => 'group_forum_id'
    belongs_to :posted_by, :class_name => 'GForgeUser', :foreign_key => 'posted_by'
    def convert_to_redmine_message_in(board)
      # I don't see a need for the GForge fields thread_id, has_followups, or most_recent_date
      message = board.messages.new(
        :author => create_or_fetch_user(posted_by),
        :subject => subject,
        :content => body.blank? ? "None" : body,
        :created_on => Time.at(post_date)
      )
      message.save!
      message
    end
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
    has_many :artifact_monitors, :class_name => "GForgeArtifactMonitor", :foreign_key => 'user_id'
    named_scope :active, :conditions => {:status => "A"}
    def convert_to_redmine_user
      user = User.new(:mail => email, :created_on => Time.at(add_date))
      user.firstname = sanitized_name(firstname)
      user.lastname = sanitized_name(lastname)
      user.type = "User"
      user.hashed_password = "5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8"  # that's 'password', FIXME user_pw
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
  
  class GForgeDocumentGroup < GForgeTable
    set_table_name "doc_groups"
    set_primary_key "doc_group"
    belongs_to :group, :class_name => "GForgeGroup", :foreign_key => 'group_id'
    has_many :documents, :class_name => "GForgeDocument", :foreign_key => 'doc_group'
  end
  
  class GForgeDocument < GForgeTable
    set_table_name "doc_data"
    belongs_to :group, :class_name => "GForgeGroup", :foreign_key => 'group_id'
    belongs_to :document_group, :class_name => "GForgeDocumentGroup", :foreign_key => 'doc_group'
  end
  
  class GForgeArtifactMonitor < GForgeTable
    set_table_name "artifact_monitor"
    belongs_to :artifact, :class_name => "GForgeArtifact"
    belongs_to :user, :class_name => "GForgeUser"
    def convert_to_redmine_watcher_on(issue)
      Watcher.create!(:watchable_type => "Issue", :watchable_id => issue.id, :user => create_or_fetch_user(user)) unless issue.watchers.map(&:user_id).include?(user_id)
    end
  end
  
  class GForgeArtifactMessage < GForgeTable
    set_table_name 'artifact_message'
    belongs_to :artifact, :class_name => "GForgeArtifact"
    belongs_to :user, :class_name => 'GForgeUser', :foreign_key => 'submitted_by'
    def convert_to_redmine_journal_on(issue)
      Journal.create!(:journalized_type => "Issue", :journalized_id => issue.id, :user => create_or_fetch_user(user), :notes => body, :created_on => Time.at(adddate))
    end
  end

  class GForgeArtifact < GForgeTable
    # TODO it looks like the Redmine equivalent of artifact_history is the combination of journal and journal entries.  Is it worthwhile to migrate over that data?
    set_table_name 'artifact'
    set_primary_key 'artifact_id'
    belongs_to :artifact_group_list, :class_name => "GForgeArtifactGroupList", :foreign_key => 'group_artifact_id'
    belongs_to :submitted_by, :class_name => 'GForgeUser', :foreign_key => 'submitted_by'
    belongs_to :assigned_to, :class_name => 'GForgeUser', :foreign_key => 'assigned_to'
    belongs_to :category, :class_name => "GForgeArtifactCategory", :foreign_key => 'category_id'
    has_many :monitors, :class_name => "GForgeArtifactMonitor", :foreign_key => 'artifact_id'
    has_many :messages, :class_name => "GForgeArtifactMessage", :foreign_key => 'artifact_id'
    def convert_to_redmine_issue_in(project)
      # I don't see a Redmine equivalent for these fields: resolution_id, close_date
      issue = Issue.new(
        :project => project, 
        :tracker => Tracker.find_by_name(artifact_group_list.corresponding_redmine_tracker_name), 
        :author => create_or_fetch_user(submitted_by),
        :description => details,
        :status => redmine_status,
        :subject => summary[0..254],
        :priority => IssuePriority.find_by_position(priority),
        :assigned_to => create_or_fetch_user(assigned_to),
        :created_on => Time.at(open_date),
        :updated_on => updated_on_for_redmine
      )
      if category
        redmine_category = project.issue_categories.find_by_name(category.category_name[0..29])
        if !redmine_category
          redmine_category = project.issue_categories.create!(:name => category.category_name[0..29], :assigned_to => create_or_fetch_user(category.auto_assign_to))
        end
        issue.category = redmine_category
      end
      issue.save!
      if assigned_to.user_id == 100
        # I fiddled around with ActiveRecord::Base.record_timestamps for a while here before falling back to SQL... seemed like one of the callbacks was causing the updated_on field
        # to be updated when I nulled out assigned_to_id
        ActiveRecord::Base.connection.execute("update issues set assigned_to_id = null where id = #{issue.id}")
      end
      issue
    end
    def updated_on_for_redmine
      if close_date && close_date != 0
        Time.at(close_date)
      elsif !messages.empty?
        Time.at(messages.last.adddate)
      else
        Time.at(open_date)
      end
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
    has_many :artifacts, :class_name => "GForgeArtifact", :foreign_key => "category_id"
  end
  
  # I experimented with memoizing this method, but it actually slowed the migration down
  def create_or_fetch_user(gforge_user)
    if user = User.find_by_mail(gforge_user.email) 
      user
    else
      showing_migrated_ids(gforge_user) do
        gforge_user.convert_to_redmine_user
      end
    end
  end

end

