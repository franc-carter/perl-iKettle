
use Device::iKettle;

my $kettle = Device::iKettle->new($ARGV[0]);

while(my $msg = $kettle->get_message()) {
    print "$msg\n";
    $kettle->process_message($msg);
    $kettle->print_status();
}
