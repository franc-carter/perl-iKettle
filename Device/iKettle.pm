package Device::iKettle;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use Sys::Syslog qw(:standard :macros);
use Carp;

use constant PORT             => 2000;
use constant STATUS_BYTE_ON   => 0b00000001;
use constant STATUS_BYTE_WARM => 0b00000010;
use constant STATUS_BYTE_65C  => 0b00000100;
use constant STATUS_BYTE_80C  => 0b00001000;
use constant STATUS_BYTE_95C  => 0b00010000;
use constant STATUS_BYTE_100C => 0b00100000;
use constant SET_ON           => "0x5";
use constant SET_OFF          => "0x0";
use constant SET_REACHED      => "0x03";
use constant SET_100C         => "0x100";
use constant SET_95C          => "0x95";
use constant SET_80C          => "0x80";
use constant SET_65C          => "0x65";
use constant WARM_START       => "0x11";
use constant WARM_END         => "0x10";
use constant WARM_5           => "0x8005";
use constant WARM_10          => "0x8010";
use constant WARM_20          => "0x8020";
use constant REMOVED          => "0x1";
use constant PROBLEM          => "0x2";

my $temperature_to_cmd = {
    65  => "set sys output 0x200",
    80  => "set sys output 0x4000",
    95  => "set sys output 0x2",
    100 => "set sys output 0x80",
};

my $on_to_cmd = {
     0 => "set sys output 0x0",
     1 => "set sys output 0x4",
};

# set sys output 0x8	Select Warm button
my $warm_to_cmd = {
     5 => "set sys output 0x8005",
    10 => "set sys output 0x8010",
    20 => "nset sys output 0x8020",
};

sub new($$)
{
    my ($class,$kettle_addr) = @_;

    openlog("iKettle at $kettle_addr", "pid", LOG_USER);


    my $self        = {};
    $self->{socket} = IO::Socket::INET->new(
                          Proto    => 'tcp',
                          PeerAddr => $kettle_addr,
                          PeerPort => PORT,
                      );
    defined($self->{socket}) || confess "Could not connect to Kettle at $kettle_addr: $!\n";
    autoflush {$self->{socket}} 1;

    $self->{address}             = $kettle_addr;
    $self->{on}                  = 0;
    $self->{warming}             = 0;
    $self->{warm_for}            = 20;
    $self->{warm_until}          = undef;
    $self->{temperature_goal}    = 100;
    $self->{reached_temperature} = undef;

    local $/ = "\r";

    $self->{socket}->print("get sys status\n");
    my $response = readline $self->{socket};
    my ($code) = ($response =~ m/^.*=(\w)/);
    if (defined($code)) {
        $self->{on}      = $code & STATUS_BYTE_ON;
        $self->{warming} = $code & STATUS_BYTE_WARM;
        if ($code & STATUS_BYTE_100C) {
            $self->{temperature_goal} = 100;
        } elsif ($code & STATUS_BYTE_95C) {
            $self->{temperature_goal} = 95;
        } elsif ($code & STATUS_BYTE_80C) {
            $self->{temperature_goal} = 80;
        } elsif ($code & STATUS_BYTE_65C) {
            $self->{temperature_goal} = 65;
        }
    }
    my $obj = bless $self, $class;

    return $obj;
}

sub print_status($)
{
    my ($self) = @_;

    my $w = $self->{warm_until};
    if (!defined($w)) {
        $w = '?';
    }

    print "Kettle at: ",$self->{address},"\n";
    print "    On: ",$self->{on},"\n";
    print "    Temperature Goal: ",$self->{temperature_goal},"C\n";
    print "    Warming: ",$self->{warming},"\n";
    print "    Warm For: ",$self->{warm_for},"\n";
    print "    Warm Until: $w\n";
}

sub _do_cmd($$)
{
    my ($self,$cmd) = @_;

    if (defined($cmd)) {
        $self->{socket}->print("$cmd\n");
    } else {
        syslog(LOG_INFO, "No command for '%s'", $cmd);
    }
}

sub on($)
{
    my ($self,$on) = @_;

    if (defined($on)) {
        my $cmd = $on_to_cmd->{$on};
        $self->_do_cmd($cmd);
    }

    return $self->{on};
}

sub temperature_goal($$)
{
    my ($self,$temperature) = @_;

    if (defined($temperature)) {
        my $cmd = $temperature_to_cmd->{$temperature};
        if (defined($cmd)) {
            $self->on(1);
            $self->_do_cmd($cmd);
        }
    }

    return $self->{temperature_goal};
}

sub warm_until($)
{
    my ($self) = @_;

    return $self->{warm_until};
}

sub warm_on($)
{
    my ($self) = @_;
    if (! $self->{warming}) {
        $self->{socket}->print("set sys output 0x8\n");
        $self->{warming} = 1; # FCC HACK
    }
}

sub warm_off($)
{
    my ($self) = @_;
    if ($self->{warming}) {
        $self->{socket}->print("set sys output 0x8\n");
        $self->{warming} = 0; # FCC HACK
    }
}

sub warm_for($$)
{
    my ($self,$minutes) = @_;

    my $cmd = $warm_to_cmd->{$minutes};
    if (defined($cmd)) {
        $self->warm_on();
        $self->_do_cmd($cmd);
    }
}

sub get_sys_status($)
{
    my ($self) = @_;

    local $/ = "\r";

    $self->{socket}->print("get sys status\n");
    my $response = readline $self->{socket};

    my $n = ($response =~ m/sys status key=(\d)/);
    if (defined($n)) {
        $self->{on}   = ($n & STATUS_BYTE_ON);
        $self->{warm} = ($n & STATUS_BYTE_WARM);
        if ($n & STATUS_BYTE_65C) {
            $self->{temperature} = 65;
        } elsif ($n & STATUS_BYTE_80C) {
            $self->{temperature} = 80;
        } elsif ($n & STATUS_BYTE_95C) {
            $self->{temperature} = 95;
        } elsif ($n & STATUS_BYTE_100C) {
            $self->{temperature} = 100;
        }
    }
}

sub process_message($)
{
    my ($self,$msg) = @_;

    my ($code) = ($msg =~ m/sys status (\w+)/);
    if (defined($code)) {
        if ($code eq SET_OFF) {
            $self->{on} = 0;
            $self->{temperature_goal} = 100;
            $self->{warming} = 0;
            $self->{warm_for} = 20;
        } elsif ($code eq SET_ON) {
            $self->{on} = 1;
        } elsif ($code eq SET_REACHED) {
            $self->{reached_temperature} = time();
        } elsif ($code eq WARM_START) {
            $self->{warming} = 1;
            $self->{warm_until} = time() + $self->{warm_for}*60;
        } elsif ($code eq WARM_END) {
            $self->{warming} = 0;
        } elsif ($code eq WARM_20) {
            $self->{warm_for} = 20;
        } elsif ($code eq WARM_10) {
            $self->{warm_for} = 10;
        } elsif ($code eq WARM_5) {
            $self->{warm_for} = 5;
        } elsif ($code eq "0x100") {
            $self->{temperature_goal} = 100;
        } elsif ($code eq "0x95") {
            $self->{temperature_goal} = 95;
        } elsif ($code eq "0x80") {
            $self->{temperature_goal} = 80;
        } elsif ($code eq "0x65") {
            $self->{temperature_goal} = 65;
        }
    }
}

sub has_message($$)
{
    my ($self,$timeout) = @_;

    my $select = IO::Select->new($self->{socket});
    my @ready  = $select->can_read($timeout);

    return ($#ready >= 0);
}

sub get_message($$)
{
    my ($self) = @_;

    local $/ = "\r";

    my $fh = $self->{socket};
    my $message = readline $fh;

    syslog(LOG_INFO, "%s", $message);

    return $message;
}

1;

