
use Device::iKettle;

my $kettle = Device::iKettle->new($ARGV[0]);

sleep(20);

# On
$kettle->_do_cmd("set sys output 0x4\n"); sleep(2);

# 95C
$kettle->_do_cmd("set sys output 0x2\n"); sleep(2);

# 100C
$kettle->_do_cmd("set sys output 0x80\n"); sleep(2);

# 80C
$kettle->_do_cmd("set sys output 0x4000\n"); sleep(2);

# 65C
$kettle->_do_cmd("set sys output 0x200\n"); sleep(2);

# Warm for on
$kettle->_do_cmd("set sys output 0x8"); sleep(2);

# Warm for 5 minutes
$kettle->_do_cmd("set sys output 0x8005"); sleep(2);

# Warm for off
$kettle->_do_cmd("set sys output 0x8"); sleep(2);

# Off
$kettle->_do_cmd("set sys output 0x0\n");
