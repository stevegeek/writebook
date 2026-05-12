require "../../spec_helper"

describe "Accounts::Role" do
  describe "default role" do
    it "creates new users as members by default" do
      user = Spec::Factories.create_user(email: "default@example.com")

      user.member?.should be_true
      user.administrator?.should be_false
    end
  end

  describe "#administrator?" do
    it "is true for users with role 'administrator'" do
      admin = Spec::Factories.create_admin(email: "admin@example.com")

      admin.administrator?.should be_true
      admin.member?.should be_false
    end

    it "is false for the default-role new user" do
      user = Accounts::User.new(role: "member")
      user.administrator?.should be_false
    end
  end

  describe "#member?" do
    it "is true when role == 'member'" do
      user = Accounts::User.new(role: "member")
      user.member?.should be_true
    end

    it "is false when role == 'administrator'" do
      user = Accounts::User.new(role: "administrator")
      user.member?.should be_false
    end
  end

  pending "can_administer?" do
    # FIXME(porting gap): Rails exposes a `can_administer?` predicate that
    # combines role + future capability checks. The Marten port currently
    # uses `administrator?` directly at every call site; if/when a broader
    # capability check is introduced, mirror the Rails test here.
  end
end
