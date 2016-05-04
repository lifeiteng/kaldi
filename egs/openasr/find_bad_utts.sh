

nnet_dir=ep0-exp/tri3_ali_fbank40_h5t2048_ReLU_NP_SVD256_DCT_smbr_0.00000001

echo "496666" | sudo -S nvidia-smi -c 0
local/cleanup/cleanup_nnet2.sh --nj 6  ~/std/data_fbank/train data_all_fbank/lang \
	$nnet_dir ~/std/data_fbank/train_cleanup

