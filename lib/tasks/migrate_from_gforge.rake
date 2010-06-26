require 'active_record'

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
    include GForgeMigrate
    saved_notified_events = Setting.notified_events
    Setting.notified_events.clear
    Project.transaction do 
      count = GForgeGroup.non_system.active.count
      GForgeGroup.non_system.active.each_with_index do |gforge_group, idx|
        puts "Creating Project from Group #{gforge_group.unix_group_name} (group_id #{gforge_group.group_id}) (#{idx+1} of #{count})"
        if Project.exists?(:name => gforge_group.group_name[0..29])
          puts "Working around '#{gforge_group.group_name}'; that's the same name as an existing project"
          gforge_group.group_name = gforge_group.group_name[0..20] + gforge_group.group_id.to_s
          puts "Set gforge_group.group_name to #{gforge_group.group_name}"
        end
        project = Project.create!(:name => gforge_group.group_name[0..29], :created_on => Time.at(gforge_group.register_time), :homepage => (gforge_group.homepage[0..254] rescue ""), :identifier => gforge_group.unix_group_name)
        gforge_group.user_group.each do |user_group|
          user = create_or_fetch_user(user_group.user)
          if user_group.group_admin?
            Member.create!(:principal => user, :project => project, :role_ids => [Role.find_by_name("Manager").id])
          else
            Member.create!(:principal => user, :project => project, :role_ids => [Role.find_by_name("Developer").id])
          end
        end
        gforge_group.artifact_groups.each do |artifact_group|
          artifact_group.artifacts.each do |artifact|
            tracker = project.trackers.find_by_name(artifact.artifact_group.corresponding_redmine_tracker_name)
            if !tracker
              project.trackers << Tracker.find_by_name(artifact.artifact_group.corresponding_redmine_tracker_name)
              tracker = project.trackers.last
            end
            project.issues.create!(
              :tracker => tracker, 
              :author => create_or_fetch_user(artifact.submitted_by),
              :description => artifact.details,
              :subject => artifact.summary)
            # FIXME map issue status, category, etc
          end
        end
        break if Project.count > 10
      end
    end
    Setting.notified_events = saved_notified_events
  end
  
  def create_or_fetch_user(gforge_user)
    if user = User.find_by_mail(gforge_user.email) 
      user
    else
      user = User.new(
      :mail => gforge_user.email, 
      :firstname => (gforge_user.realname.split(" ")[0] rescue gforge_user.realname), 
      :created_on => Time.at(gforge_user.add_date)
      )
      user.lastname = (gforge_user.realname.split(" ")[1] rescue "None") || "None"
      user.type = "User"
      user.hashed_password = gforge_user.user_pw
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

require 'lib/tasks/gforge_models'