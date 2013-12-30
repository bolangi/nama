process_command("add_tracks Stereo L_front R_front Center Subwoofer L_inverted Right R-L L_rear R_rear");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:3,R3,4,R4,5,R5,6,R6,7,R7,8,R8,9,R9,10,R10,11,R11,12,R12 -i:alsa,default

# post-input processing

-a:R3  
-a:3  -chcopy:1,2
-a:R4  
-a:4  -chcopy:1,2
-a:R5  
-a:5  -chcopy:1,2
-a:6  -chcopy:1,2
-a:R6  
-a:R7  
-a:7  -chcopy:1,2
-a:R8  
-a:8  -chcopy:1,2
-a:R9  
-a:9  -chcopy:1,2
-a:R10  
-a:10  -chcopy:1,2
-a:11  -chcopy:1,2
-a:R11  
-a:R12  
-a:12  -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3,4,5,6,7,8,9,10,11,12 -o:loop,Master_in
-a:R10 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R-L_1.wav
-a:R11 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_rear_1.wav
-a:R12 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_rear_1.wav
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Stereo_1.wav
-a:R4 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_front_1.wav
-a:R5 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_front_1.wav
-a:R6 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Center_1.wav
-a:R7 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Subwoofer_1.wav
-a:R8 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_inverted_1.wav
-a:R9 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Right_1.wav


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 1: add_tracks Stereo L_front R_front Center Subwoofer L_inverted Right R-L L_rear R_rear");

process_command("add_bunch all Stereo L_front R_front Center Subwoofer L_inverted Right R-L L_rear R_rear");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:3,R3,4,R4,5,R5,6,R6,7,R7,8,R8,9,R9,10,R10,11,R11,12,R12 -i:alsa,default

# post-input processing

-a:3  -chcopy:1,2
-a:R3  
-a:4  -chcopy:1,2
-a:R4  
-a:5  -chcopy:1,2
-a:R5  
-a:R6  
-a:6  -chcopy:1,2
-a:7  -chcopy:1,2
-a:R7  
-a:8  -chcopy:1,2
-a:R8  
-a:R9  
-a:9  -chcopy:1,2
-a:10  -chcopy:1,2
-a:R10  
-a:R11  
-a:11  -chcopy:1,2
-a:12  -chcopy:1,2
-a:R12  

# audio outputs

-a:1 -o:alsa,default
-a:3,4,5,6,7,8,9,10,11,12 -o:loop,Master_in
-a:R10 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R-L_1.wav
-a:R11 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_rear_1.wav
-a:R12 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_rear_1.wav
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Stereo_1.wav
-a:R4 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_front_1.wav
-a:R5 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_front_1.wav
-a:R6 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Center_1.wav
-a:R7 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Subwoofer_1.wav
-a:R8 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_inverted_1.wav
-a:R9 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Right_1.wav


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 2: add_bunch all Stereo L_front R_front Center Subwoofer L_inverted Right R-L L_rear R_rear");

process_command("add_sub_bus R-L");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:3,R3,4,R4,5,R5,6,R6,7,R7,8,R8,9,R9,11,R11,12,R12 -i:alsa,default

# post-input processing

-a:R3  
-a:3  -chcopy:1,2
-a:R4  
-a:4  -chcopy:1,2
-a:5  -chcopy:1,2
-a:R5  
-a:R6  
-a:6  -chcopy:1,2
-a:R7  
-a:7  -chcopy:1,2
-a:R8  
-a:8  -chcopy:1,2
-a:9  -chcopy:1,2
-a:R9  
-a:R11  
-a:11  -chcopy:1,2
-a:R12  
-a:12  -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3,4,5,6,7,8,9,11,12 -o:loop,Master_in
-a:R11 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_rear_1.wav
-a:R12 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_rear_1.wav
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Stereo_1.wav
-a:R4 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_front_1.wav
-a:R5 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_front_1.wav
-a:R6 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Center_1.wav
-a:R7 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Subwoofer_1.wav
-a:R8 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_inverted_1.wav
-a:R9 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Right_1.wav


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 3: add_sub_bus R-L");

process_command("Stereo move_to_bus null");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:R3,4,R4,5,R5,6,R6,7,R7,8,R8,9,R9,11,R11,12,R12 -i:alsa,default

# post-input processing

-a:R3  
-a:R4  
-a:4  -chcopy:1,2
-a:5  -chcopy:1,2
-a:R5  
-a:R6  
-a:6  -chcopy:1,2
-a:R7  
-a:7  -chcopy:1,2
-a:R8  
-a:8  -chcopy:1,2
-a:9  -chcopy:1,2
-a:R9  
-a:R11  
-a:11  -chcopy:1,2
-a:R12  
-a:12  -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:4,5,6,7,8,9,11,12 -o:loop,Master_in
-a:R11 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_rear_1.wav
-a:R12 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_rear_1.wav
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Stereo_1.wav
-a:R4 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_front_1.wav
-a:R5 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_front_1.wav
-a:R6 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Center_1.wav
-a:R7 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Subwoofer_1.wav
-a:R8 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_inverted_1.wav
-a:R9 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Right_1.wav


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 4: Stereo move_to_bus null");

process_command("R-L    move_to_bus null");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:R3,4,R4,5,R5,6,R6,7,R7,8,R8,9,R9,11,R11,12,R12 -i:alsa,default

# post-input processing

-a:R3  
-a:4  -chcopy:1,2
-a:R4  
-a:R5  
-a:5  -chcopy:1,2
-a:6  -chcopy:1,2
-a:R6  
-a:7  -chcopy:1,2
-a:R7  
-a:8  -chcopy:1,2
-a:R8  
-a:9  -chcopy:1,2
-a:R9  
-a:11  -chcopy:1,2
-a:R11  
-a:12  -chcopy:1,2
-a:R12  

# audio outputs

-a:1 -o:alsa,default
-a:4,5,6,7,8,9,11,12 -o:loop,Master_in
-a:R11 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_rear_1.wav
-a:R12 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_rear_1.wav
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Stereo_1.wav
-a:R4 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_front_1.wav
-a:R5 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/R_front_1.wav
-a:R6 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Center_1.wav
-a:R7 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Subwoofer_1.wav
-a:R8 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/L_inverted_1.wav
-a:R9 -f:s16_le,1,44100,i -o:/tmp/nama-test/test-convert51-incremental/.wav/Right_1.wav


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 5: R-L    move_to_bus null");

process_command("for all; rec_defeat; remove_fader_effect vol; remove_fader_effect pan");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:4,5,6,7,8,9,11,12 -i:alsa,default

# post-input processing

-a:4  
-a:5  
-a:6  
-a:7  
-a:8  
-a:9  
-a:11  
-a:12  

# audio outputs

-a:1 -o:alsa,default
-a:4,5,6,7,8,9,11,12 -o:loop,Master_in


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 6: for all; rec_defeat; remove_fader_effect vol; remove_fader_effect pan");

process_command("for L_front R_front Center Subwoofer L_inverted Right; source track Stereo");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:3,11,12 -i:alsa,default
-a:4,5,6,7,8,9 -i:loop,Stereo_out

# post-input processing

-a:3  
-a:11  
-a:12  

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Stereo_out
-a:4,5,6,7,8,9,11,12 -o:loop,Master_in


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 7: for L_front R_front Center Subwoofer L_inverted Right; source track Stereo");

process_command("for L_inverted Right; move_to_bus R-L");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:3,11,12 -i:alsa,default
-a:4,5,6,7 -i:loop,Stereo_out

# post-input processing

-a:3  
-a:11  
-a:12  

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Stereo_out
-a:4,5,6,7,11,12 -o:loop,Master_in


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 8: for L_inverted Right; move_to_bus R-L");

process_command("for L_rear R_rear; source track R-L");
$expected_setup_lines = <<EXPECTED;
# ecasound chainsetup file

# general

-z:mixmode,sum -G:jack,Nama,send -G:jack,Nama,send -b 256 -z:db,100000 -z:nointbuf

# audio inputs

-a:1 -i:loop,Master_in
-a:10 -i:loop,R-L_in
-a:11,12 -i:loop,R-L_out
-a:3 -i:alsa,default
-a:4,5,6,7,8,9 -i:loop,Stereo_out

# post-input processing

-a:3  

# audio outputs

-a:1 -o:alsa,default
-a:10 -o:loop,R-L_out
-a:3 -o:loop,Stereo_out
-a:4,5,6,7,11,12 -o:loop,Master_in
-a:8,9 -o:loop,R-L_in


EXPECTED
gen_alsa();
check_setup("Stereo to 5.1 converter
   line 9: for L_rear R_rear; source track R-L");

