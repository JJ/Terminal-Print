use v6.d.PREVIEW;
unit module Terminal::Print::RawInput;

# For TTY raw mode
use Term::termios;


#| Convert an input stream to a Supply of individual characters
#  Reads bytes in order to work around lower-layer grapheme combiner handling
#  (which will make the input seem to be on a one-character delay).
sub raw-input-supply(IO::Handle $input = $*IN) is export {
    # If a TTY, convert to raw mode, saving current mode first
    my $fd = $input.native-descriptor;
    my $saved-termios;
    if $input.t {
        $saved-termios = Term::termios.new(:$fd).getattr;
        Term::termios.new(:$fd).getattr.makeraw.setattr(:DRAIN);
    }

    # Cancelable character supply loop; emits a character as soon as any
    # collected bytes are decodable.  jnthn++ for explaining this supply variant
    # in https://rt.perl.org/Public/Bug/Display.html?id=130716#txn-1448844
    my $s    = Supplier::Preserving.new;
    my $done = False;
    start {
        # Make sure the input handle is opened in *this thread*, otherwise
        # libuv gets cranky about thread-crossing I/O handles
        my $in = open("/dev/fd/$fd", :r);

        LOOP: until $done {
            my $buf = Buf.new;

            # TimToady++ for suggesting this decode loop idiom
            repeat {
                my $b = $in.read(1) or last LOOP;
                $buf.push($b);
            } until $done || try my $c = $buf.decode;

            $s.emit($c) unless $done;
        }
    }
    $s.Supply.on-close: {
        # Restore saved TTY mode if any
        $saved-termios.setattr(:DRAIN) if $saved-termios;
        $done = True;
    }
}
