
use Device::iKettle;

my $kettle = Device::iKettle->new($ARGV[0]);

$kettle->on(1);
$kettle->temperature_goal($ARGV[1]);
