namespace :hermes do
  desc "Print pending Hermes events as signed JSON lines (read by bin/hermes-relay on the host)"
  task drain: :environment do
    Hermes.drain.each { puts _1 }
  end
end
