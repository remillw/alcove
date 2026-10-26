require "test_helper"

class CreditsTest < ActiveSupport::TestCase
  setup { @user = users(:member) }

  test "a movement updates the cached balance in the same transaction" do
    Credits.post!(user: @user, amount: -2, kind: :reserve, key: "t:1")
    assert_equal 3, @user.reload.credit_balance
    assert_equal @user.credit_balance, @user.credit_entries.sum(:amount)
  end

  test "replaying the same key writes once" do
    2.times { Credits.post!(user: @user, amount: -1, kind: :reserve, key: "t:same") }
    assert_equal 4, @user.reload.credit_balance
    assert_equal 1, CreditEntry.where(idempotency_key: "t:same").count
  end

  test "the balance never goes negative" do
    assert_raises(Credits::InsufficientBalance) { Credits.post!(user: @user, amount: -6, kind: :reserve, key: "t:2") }
    assert_equal 5, @user.reload.credit_balance
  end

  test "ledger entries are append-only" do
    entry = Credits.post!(user: @user, amount: 1, kind: :grant, key: "t:3")
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(amount: 100) }
  end

  test "drift between the cache and the ledger is detected" do
    assert_empty Credits.drifted_user_ids
    @user.update_columns(credit_balance: 50)
    assert_equal [ @user.id ], Credits.drifted_user_ids
  end
end

class CreditsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "ten tabs spending at once can't spend more than the balance" do
    user = User.create!(credit_balance: 0)
    Credits.post!(user:, amount: 3, kind: :grant, key: "conc:grant:#{user.id}")
    results = 10.times.map { |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Credits.post!(user: User.find(user.id), amount: -1, kind: :reserve, key: "conc:#{user.id}:#{i}")
          :ok
        rescue Credits::InsufficientBalance
          :refused
        end
      end
    }.map(&:value)

    assert_equal 3, results.count(:ok)
    assert_equal 0, user.reload.credit_balance
    assert_equal 0, user.credit_entries.sum(:amount)
  ensure
    user&.destroy
  end
end
