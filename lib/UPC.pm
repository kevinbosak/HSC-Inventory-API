package UPC;

use Imager;

my $CODES = {
    0 => '0001101',
    1 => '0011001',
    2 => '0010011',
    3 => '0111101',
    4 => '0100011',
    5 => '0110001',
    6 => '0101111',
    7 => '0111011',
    8 => '0110111',
    9 => '0001011',
};

sub upc {
    my ($num, $size) = @_;
    $size ||= 1;

    my $whitespace = 10;
    my $xsize = $size * (95+$whitespace*2);
    my $ysize = $size * (30+$whitespace*2);

    my $img = Imager->new(xsize => $xsize, ysize => $ysize, channels => 1); 
    $img->box(filled => 1, color => 'white');
    $num = sprintf('%010d', $num);
    my @digits = (0, split('', $num));

    # calculate checksum;
    my $checksum = 0;
    my $temp = 0;
    $temp += $_ for @digits[0,2,4,6,8,10];
    $temp *= 3;
    $temp += $_ for @digits[1,3,5,7,9];
    my $temp2 = $temp % 10;
    $checksum = 10-$temp2;

    my $left = $size * $whitespace;
    my $top = $size * $whitespace/2;
    my $bottom = $ysize-$size*$whitespace;

    # draw guard bars
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    $left += $size;
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    # draw zero, first five digits
    for my $digit (@digits[0..5]) {
        my $code = $CODES->{$digit};
        for my $bit (split('', $code)) {
            if ($bit) {
                for (1..$size) {
                    $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
                    $left++;
                }
            } else {
                $left += $size;
            }
        }
    }
    # draw guard bars
    $left += $size;
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    $left += $size;
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    $left += $size;

    # draw last five digits, checksum
    for my $digit (@digits[6..10], $checksum) {
        my $code = $CODES->{$digit};
        for my $bit (split('', $code)) {
            if (!$bit) {
                for (1..$size) {
                    $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
                    $left++;
                }
            } else {
                $left += $size;
            }
        }
    }
    # draw guard bars
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    $left += $size;
    for (1..$size) {
        $img->line(color => 'black', x1 => $left, x2 => $left, y1 => $top, y2 => $bottom);
        $left++;
    }
    return $img;
}

1;
