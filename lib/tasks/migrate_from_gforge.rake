require 'active_record'
require 'lib/tasks/gforge_models'

namespace :redmine do

  task :create_anonymous_user => :environment do
    user = AnonymousUser.new(:firstname => "Anonymous", :lastname => "User", :mail => "anonymous@example.org", :type => "AnonymousUser")
    user.login = "anonymous"
    user.save!
  end
  
  task :gforge_migration_default_data => :environment do
    Tracker.create!(:name => "Patch", :is_in_chlog => true, :is_in_roadmap => false)
  end
  
  # TODO I bet there's some way to be able to run rake db:reset:migrate as a dependency here... but when I do
  # that, the Roles all have blank permission attribute.  I added a Role.reset_column_information to no avail... what am I missing here?
  task :migrate_from_gforge => [:environment, 'redmine:load_default_data', 'redmine:gforge_migration_default_data', 'redmine:create_anonymous_user'] do 
    without_notifications do
      include GForgeMigrate
      if ENV['GFORGE_GROUP_TO_MIGRATE']
        puts "Migrating #{ENV['GFORGE_GROUP_TO_MIGRATE']}"
        migrate_group(GForgeGroup.find_by_unix_group_name(ENV['GFORGE_GROUP_TO_MIGRATE']))
      else
        count = GForgeGroup.non_system.active.count
        GForgeGroup.non_system.active.find(:all, :order => "id asc").each_with_index do |gforge_group, idx|
          puts "Creating Project from Group #{gforge_group.unix_group_name} (group_id #{gforge_group.group_id}) (#{idx+1} of #{count})"
          migrate_group(gforge_group)
        end
      end
      # TODO migrate over all other GForge users - these are the ones who have not submitted a bug or joined a project or anything
    end
  end
  
  def without_notifications
    saved_notified_events = Setting.notified_events
    Setting.notified_events.clear
    yield
    Setting.notified_events = saved_notified_events
  end
  
  def showing_migrated_ids(object)
    result = yield object
    puts "Migrated #{object.class.class_name} #{object.id} to #{result.class} #{result.id}"
    result
  end
  
  def migrate_group(gforge_group)
    #Project.transaction do 
      if Project.exists?(:name => gforge_group.group_name[0..29])
        puts "Working around '#{gforge_group.group_name}'; that's the same name as an existing project"
        gforge_group.group_name = gforge_group.group_name[0..20] + gforge_group.group_id.to_s
        puts "Set gforge_group.group_name to #{gforge_group.group_name}"
      end
      project = Project.create!(
        :name => gforge_group.group_name[0..29], 
        :created_on => Time.at(gforge_group.register_time), 
        :homepage => (gforge_group.homepage[0..254] rescue ""), 
        :description => gforge_group.short_description,
        :status => gforge_group.redmine_status,
        :identifier => gforge_group.unix_group_name
      )
      project.enabled_modules.create!(:name => "issue_tracking") if gforge_group.use_tracker
      project.enabled_modules.create!(:name => "boards") if gforge_group.use_forum
      project.enabled_modules.create!(:name => "document") if gforge_group.use_docman
      gforge_group.user_group.each do |user_group|
        user = create_or_fetch_user(user_group.user)
        if user_group.group_admin?
          role_name = "Manager"
        else
          role_name = "Developer"
        end
        Member.create!(:principal => user, :project => project, :role_ids => [Role.find_by_name(role_name).id])
      end
      gforge_group.artifact_group_lists.each do |artifact_group_list|
        project.trackers << Tracker.find_by_name(artifact_group_list.corresponding_redmine_tracker_name) unless project.trackers.find_by_name(artifact_group_list.corresponding_redmine_tracker_name)
        artifact_group_list.artifacts.each do |artifact|
          issue = showing_migrated_ids(artifact) do
            artifact.convert_to_redmine_issue_in(project)
          end
          artifact.monitors.each do |artifact_monitor|
            showing_migrated_ids(artifact_monitor) do |artifact_monitor|
              artifact_monitor.convert_to_redmine_watcher_on(issue)
            end
          end
          artifact.messages.each do |artifact_message|
            showing_migrated_ids(artifact_message) do |artifact_message|
              artifact_message.convert_to_redmine_journal_on(issue)
            end
          end
          artifact.files.each do |artifact_file|
            showing_migrated_ids(artifact_file) do |artifact_file|
              artifact_file.convert_to_redmine_attachment_to(issue)
            end
          end
        end
      end
      gforge_group.forum_groups.active.each do |forum_group|
        board = forum_group.convert_to_redmine_board_in(project)
        board_threads = {}
        forum_group.forum_messages.find(:all, :order => "msg_id asc").each do |forum_message|
          message = showing_migrated_ids(forum_message) do 
            forum_message.convert_to_redmine_message_in(board)
          end
          board_threads[forum_message.id] = message
          if forum_message.is_followup_to
            possible_parent = board_threads[forum_message.is_followup_to]
            # Redmine has flat message replies, GForge has nested replies
            # See http://www.redmine.org/boards/1/topics/15509 for more details
            # So, flattening the GForge threads
            if possible_parent && possible_parent.parent
              message.parent = possible_parent.parent
            else
              message.parent = possible_parent
            end
            message.save!
          end
        end
      end
    #end
  end
  
end
