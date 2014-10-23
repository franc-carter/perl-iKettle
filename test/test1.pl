
use Device::iKettle;

my $kettle = Device::iKettle->new($ARGV[0]);

while(1) {
    $kettle->has_message(1);
    my $msg = $kettle->get_message();
    print "Message: $msg\n";
    $kettle->process_message($msg);
    $kettle->print_status();
}
