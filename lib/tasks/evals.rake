namespace :evals do
  desc "Run the behaviour evals against the real API (every character x evals/cases.yml), write evals/results/"
  task run: :environment do
    Evals::Runner.new(only: ENV["ONLY"]).run
  end
end
