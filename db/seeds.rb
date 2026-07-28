require "securerandom"

puts "🧹 Cleaning database..."

Match.destroy_all
TeamMembership.destroy_all
Team.destroy_all
User.destroy_all

puts "👤 Creating users..."

password = "password123"

create_user = lambda do |first_name:, last_name:, email:, account_type:|
  User.create!(
    first_name: first_name,
    last_name: last_name,
    email: email,
    password: password,
    password_confirmation: password,
    account_type: account_type
  )
end

# --------------------------------------------------
# MANAGERS
# --------------------------------------------------

james = create_user.call(
  first_name: "James",
  last_name: "Mensah",
  email: "manager@example.com",
  account_type: "manager"
)

sarah = create_user.call(
  first_name: "Sarah",
  last_name: "Williams",
  email: "manager2@example.com",
  account_type: "manager"
)

daniel = create_user.call(
  first_name: "Daniel",
  last_name: "Boateng",
  email: "othermanager@example.com",
  account_type: "manager"
)

pending_manager = create_user.call(
  first_name: "Michael",
  last_name: "Owusu",
  email: "pendingmanager@example.com",
  account_type: "manager"
)

# Your User callback may automatically set new managers to "pending",
# so approve the managers after they have been created.
james.update!(manager_verification_status: "approved")
sarah.update!(manager_verification_status: "approved")
daniel.update!(manager_verification_status: "approved")
pending_manager.update!(manager_verification_status: "pending")

# --------------------------------------------------
# PLAYERS
# --------------------------------------------------

player_details = [
  ["Kwame", "Asante", "player@example.com"],
  ["Jordan", "Smith", "player2@example.com"],
  ["Andre", "Johnson", "player3@example.com"],
  ["Nathan", "Brown", "player4@example.com"],
  ["Samuel", "Wilson", "player5@example.com"],
  ["Marcus", "Taylor", "player6@example.com"],
  ["Isaac", "Thomas", "player7@example.com"],
  ["Leon", "Walker", "player8@example.com"],
  ["Aaron", "Roberts", "player9@example.com"],
  ["Joshua", "White", "player10@example.com"],
  ["Benjamin", "Harris", "player11@example.com"],
  ["Ryan", "Martin", "player12@example.com"],
  ["Kofi", "Agyeman", "player13@example.com"],
  ["Ethan", "Clarke", "player14@example.com"],
  ["Luke", "Anderson", "player15@example.com"],
  ["Jayden", "King", "player16@example.com"],
  ["Callum", "Evans", "player17@example.com"],
  ["Owen", "Davies", "player18@example.com"],
  ["Reece", "Green", "player19@example.com"],
  ["Tyler", "Baker", "player20@example.com"],
  ["Alex", "Morgan", "pendingplayer@example.com"]
]

players = player_details.map do |first_name, last_name, email|
  create_user.call(
    first_name: first_name,
    last_name: last_name,
    email: email,
    account_type: "player"
  )
end

puts "⚽ Creating teams..."

hackney_fc = Team.create!(
  name: "Hackney United FC",
  description: "A competitive Sunday League football team based in East London.",
  invite_code: SecureRandom.hex(4).upcase
)

south_london_fc = Team.create!(
  name: "South London Athletic",
  description: "A community Sunday League team competing across South London.",
  invite_code: SecureRandom.hex(4).upcase
)

puts "🤝 Creating manager memberships..."

TeamMembership.create!(
  user: james,
  team: hackney_fc,
  role: "manager",
  preferred_position: "CM",
  status: "approved"
)

TeamMembership.create!(
  user: sarah,
  team: hackney_fc,
  role: "manager",
  preferred_position: "CB",
  status: "approved"
)

TeamMembership.create!(
  user: daniel,
  team: south_london_fc,
  role: "manager",
  preferred_position: "GK",
  status: "approved"
)

# Useful for testing that an unverified manager cannot manage matches.
TeamMembership.create!(
  user: pending_manager,
  team: hackney_fc,
  role: "manager",
  preferred_position: "CM",
  status: "approved"
)

puts "🏃 Creating player memberships..."

positions = %w[
  GK
  CB
  LB
  RB
  CDM
  CM
  LW
  RW
  ST
]

# First 10 approved players join Hackney United.
players.first(10).each_with_index do |player, index|
  TeamMembership.create!(
    user: player,
    team: hackney_fc,
    role: "player",
    preferred_position: positions[index % positions.length],
    status: "approved"
  )
end

# Next 10 approved players join South London Athletic.
players.slice(10, 10).each_with_index do |player, index|
  TeamMembership.create!(
    user: player,
    team: south_london_fc,
    role: "player",
    preferred_position: positions[index % positions.length],
    status: "approved"
  )
end

# Final player has requested to join Hackney United but is awaiting approval.
TeamMembership.create!(
  user: players.last,
  team: hackney_fc,
  role: "player",
  preferred_position: "ST",
  status: "pending"
)

puts "📅 Creating matches..."

hackney_matches = [
  {
    opponent: "Camden Rovers",
    match_type: "league",
    location: "Hackney Marshes, Pitch 4",
    kickoff_time: 1.week.from_now.change(hour: 14, min: 0)
  },
  {
    opponent: "East London Lions",
    match_type: "cup",
    location: "Mabley Green Sports Centre",
    kickoff_time: 2.weeks.from_now.change(hour: 13, min: 30)
  },
  {
    opponent: "Islington Athletic",
    match_type: "friendly",
    location: "Market Road Football Pitches",
    kickoff_time: 3.weeks.from_now.change(hour: 15, min: 0)
  },
  {
    opponent: "Tower Hamlets FC",
    match_type: "league",
    location: "Stepney Green Astroturf",
    kickoff_time: 4.weeks.from_now.change(hour: 14, min: 30)
  }
]

hackney_matches.each do |attributes|
  hackney_fc.matches.create!(attributes)
end

south_london_matches = [
  {
    opponent: "Brixton United",
    match_type: "league",
    location: "Clapham Common Football Pitches",
    kickoff_time: 1.week.from_now.change(hour: 12, min: 30)
  },
  {
    opponent: "Croydon Rangers",
    match_type: "cup",
    location: "Crystal Palace National Sports Centre",
    kickoff_time: 3.weeks.from_now.change(hour: 14, min: 0)
  },
  {
    opponent: "Peckham Town",
    match_type: "friendly",
    location: "Dulwich Sports Ground",
    kickoff_time: 5.weeks.from_now.change(hour: 13, min: 0)
  }
]

south_london_matches.each do |attributes|
  south_london_fc.matches.create!(attributes)
end

puts
puts "✅ Seed completed successfully!"
puts "--------------------------------------------------"
puts "Users: #{User.count}"
puts "Teams: #{Team.count}"
puts "Memberships: #{TeamMembership.count}"
puts "Matches: #{Match.count}"
puts "--------------------------------------------------"
puts "Approved Hackney manager:"
puts "  Email: manager@example.com"
puts "  Password: #{password}"
puts
puts "Approved manager of another team:"
puts "  Email: othermanager@example.com"
puts "  Password: #{password}"
puts
puts "Unverified manager:"
puts "  Email: pendingmanager@example.com"
puts "  Password: #{password}"
puts
puts "Player:"
puts "  Email: player@example.com"
puts "  Password: #{password}"
puts
puts "Hackney team ID: #{hackney_fc.id}"
puts "South London team ID: #{south_london_fc.id}"
puts "Hackney invite code: #{hackney_fc.invite_code}"
puts "South London invite code: #{south_london_fc.invite_code}"
puts "--------------------------------------------------"
