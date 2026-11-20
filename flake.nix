# kai-box holds NixOS modules, not packages. Customer Kaifiles declare it with
# Input("kai-box", ...) and name its files with InputModules, which kai
# imports as a flake input, so it needs a flake with no outputs.
{
  outputs = _: { };
}
