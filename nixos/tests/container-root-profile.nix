{
  name = "simple-container";

  containers = {
    machine = { pkgs, ... }: {
      users.users.root.packages = with pkgs; [
        hello
      ];
    };
    noprofile = {};
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    noprofile.wait_for_unit("multi-user.target")
    machine.succeed("hello")
    machine.execute("sleep 3600")
    noprofile.fail("hello")
    machine.shutdown()
    noprofile.shutdown()
  '';
}
