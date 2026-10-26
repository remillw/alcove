namespace :evals do
  desc "Run the behaviour evals against the real API (every character x evals/cases.yml), write evals/results/"
  task run: :environment do
    Evals::Runner.new(only: ENV["ONLY"]).run
  end
end

namespace :evals do
  desc "Simulated users talk to every character (TURNS=6 ONLY=ada PERSONAS=beginner,sceptic), a critic reviews, report in evals/simulations/"
  task simulate: :environment do
    Evals::Simulator.new(turns: ENV.fetch("TURNS", 6).to_i, only: ENV["ONLY"], personas: ENV["PERSONAS"]).run
  end
end
