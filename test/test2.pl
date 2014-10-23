
use Device::iKettle;

my $kettle = Device::iKettle->new($ARGV[0]);

$kettle->on(1);
sleep(20);
$kettle->temperature_goal(65);
sleep(5);
$kettle->warm_for(5);
sleep(5);
$kettle->on(0);
