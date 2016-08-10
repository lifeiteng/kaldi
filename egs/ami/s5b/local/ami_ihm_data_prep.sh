#!/bin/bash

# Copyright 2014  University of Edinburgh (Author: Pawel Swietojanski)
#           2016  Johns Hopkins University (Author: Daniel Povey)
# AMI Corpus training data preparation
# Apache 2.0

# Note: this is called by ../run.sh.

# To be run from one directory above this script.

. ./path.sh

#check existing directories
if [ $# -ne 2 ] || [ "$2" != "ihm" ]; then
  echo "Usage: $0 /path/to/AMI ihm"
  echo "e.g. $0 /foo/bar/AMI ihm"
  echo "note: the 2nd 'ihm' argument is for compatibility with other scripts."
  exit 1;
fi

AMI_DIR=$1

SEGS=data/local/annotations/train.txt
dir=data/local/ihm/train
odir=data/ihm/train_orig
mkdir -p $dir

# Audio data directory check
if [ ! -d $AMI_DIR ]; then
  echo "Error: $AMI_DIR directory does not exists."
  exit 1;
fi

# And transcripts check
if [ ! -f $SEGS ]; then
  echo "Error: File $SEGS no found (run ami_text_prep.sh)."
  exit 1;
fi


# find headset wav audio files only
find $AMI_DIR -iname '*.Headset-*.wav' | sort > $dir/wav.flist
n=`cat $dir/wav.flist | wc -l`
echo "In total, $n headset files were found."
[ $n -ne 687 ] && \
  echo "Warning: expected 687 (168 mtgs x 4 mics + 3 mtgs x 5 mics) data files, found $n"

# (1a) Transcriptions preparation
# here we start with normalised transcriptions, the utt ids follow the convention
# AMI_MEETING_CHAN_SPK_STIME_ETIME
# AMI_ES2011a_H00_FEE041_0003415_0003484
# we use uniq as some (rare) entries are doubled in transcripts

awk '{meeting=$1; channel=$2; speaker=$3; stime=$4; etime=$5;
 printf("AMI_%s_%s_%s_%07.0f_%07.0f", meeting, channel, speaker, int(100*stime+0.5), int(100*etime+0.5));
 for(i=6;i<=NF;i++) printf(" %s", $i); printf "\n"}' $SEGS | sort | uniq > $dir/text

# (1b) Make segment files from transcript

awk '{
       segment=$1;
       split(segment,S,"[_]");
       audioname=S[1]"_"S[2]"_"S[3]; startf=S[5]; endf=S[6];
       print segment " " audioname " " startf*10/1000 " " endf*10/1000 " "
}' < $dir/text > $dir/segments

# (1c) Make wav.scp file.

sed -e 's?.*/??' -e 's?.wav??' $dir/wav.flist | \
 perl -ne 'split; $_ =~ m/(.*)\..*\-([0-9])/; print "AMI_$1_H0$2\n"' | \
  paste - $dir/wav.flist > $dir/wav1.scp

#Keep only  train part of waves
awk '{print $2}' $dir/segments | sort -u | join - $dir/wav1.scp >  $dir/wav2.scp

#replace path with an appropriate sox command that select single channel only
awk '{print $1" sox -c 1 -t wavpcm -s "$2" -t wavpcm - |"}' $dir/wav2.scp > $dir/wav.scp

# (1d) reco2file_and_channel
cat $dir/wav.scp \
 | perl -ane '$_ =~ m:^(\S+)(H0[0-4])\s+.*\/([IETB].*)\.wav.*$: || die "bad label $_";
              print "$1$2 $3 A\n"; ' > $dir/reco2file_and_channel || exit 1;


# In this data-prep phase we adapt to the session and speaker [later on we may
# split into shorter pieces]., We use the 0th, 1st and 3rd underscore-separated
# fields of the utterance-id as the speaker-id,
# e.g. 'AMI_EN2001a_IHM_FEO065_0090130_0090775' becomes 'AMI_EN2001a_FEO065'.
awk '{print $1}' $dir/segments | \
  perl -ane 'chop; @A = split("_", $_); $spkid = join("_", @A[0,1,3]); print "$_ $spkid\n";'  \
  >$dir/utt2spk || exit 1;


awk '{print $1}' $dir/segments | \
  perl -ane '$_ =~ m:^(\S+)([FM][A-Z]{0,2}[0-9]{3}[A-Z]*)(\S+)$: || die "bad label $_";
          print "$1$2$3 $1$2\n";' > $dir/utt2spk || exit 1;

utils/utt2spk_to_spk2utt.pl <$dir/utt2spk >$dir/spk2utt || exit 1;

# Copy stuff into its final location
mkdir -p $odir
for f in spk2utt utt2spk wav.scp text segments reco2file_and_channel; do
  cp $dir/$f $odir/$f || exit 1;
done

utils/validate_data_dir.sh --no-feats $odir || exit 1;

echo AMI IHM data preparation succeeded.
