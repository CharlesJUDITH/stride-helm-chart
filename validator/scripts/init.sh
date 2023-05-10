#!/bin/bash
set -x

#Install utils
apt update && apt -y --no-install-recommends install ca-certificates curl jq > /dev/null 2>&1

# fail fast should there be a problem installing curl / jq packages
type curl || exit 1
type jq || exit 1

# If Address book is enabled, download it
if [ "$STRIDE_ADDRBOOK_ENABLED" == true ]; then
  curl -s "$STRIDE_ADDRBOOK_URL" > "$STRIDE_HOME/config/addrbook.json"
fi

#Check if Home data exists, if not create it.
if [ ! -d "$STRIDE_HOME/data" ]
then
mkdir -p $STRIDE_HOME/data
# Init the chain
/usr/bin/strided init --chain-id "$STRIDE_CHAIN_ID" "$STRIDE_MONIKER"

# If the node is a validator, do tx to create the validator
# Make sure the Validator has fully synced before running 
# if $STRIDE_VALIDATOR; then
#   strided tx staking create-validator \
#     --from "<key-name>" \
#     --amount "1000000uhuahua" \
#     --pubkey "$(strided tendermint show-validator)" \
#     --chain-id "$STRIDE_CHAIN_ID" \
#     --moniker "$STRIDE_MONIKER" \
#     --commission-max-change-rate 0.01 \
#     --commission-max-rate 0.20 \
#     --commission-rate 0.10 \
#     --min-self-delegation 1 \
#     --details "<details>" \
#     --security-contact "<contact>" \
#     --website "<website>" \
#     --gas-prices "1uhuahua"
# fi

cd "$STRIDE_HOME/data" || exit
curl -s "$STRIDE_NET/genesis.json" > "$STRIDE_HOME/config/genesis.json"
if [ "$STRIDE_STATESYNC_ENABLE" == true ]; then
  echo "state-sync is enabled, figure the right trust height & derive its hash"

  export SNAP_RPC1="{{ .Values.state_sync.rpc1 }}"
  export SNAP_RPC2="{{ .Values.state_sync.rpc2 }}"

  LATEST_HEIGHT=$(curl -Ls "$SNAP_RPC1/block" | jq -r .result.block.header.height)
  HEIGHT_OFFSET="{{ .Values.state_sync.height_offset }}"
  BLOCK_HEIGHT=$((LATEST_HEIGHT - HEIGHT_OFFSET))
  TRUST_HASH=$(curl -Ls "$SNAP_RPC1/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  echo "TRUST HEIGHT: $BLOCK_HEIGHT"
  echo "TRUST HASH: $TRUST_HASH"

  export STRIDE_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
  export STRIDE_STATESYNC_TRUST_HASH=$TRUST_HASH

else
  if [ "$STRIDE_CHAIN_ID" == "stride-1" ]; then
    apt -y --no-install-recommends install aria2 lz4 liblz4-tool wget > /dev/null 2>&1
    case "$SNAPSHOT_PROVIDER" in

      "polkachu")
        SNAPSHOT_URL=$(curl -s https://polkachu.com/tendermint_snapshots/stride | grep tar.lz4 | head -n1 | grep -io '<a href=['"'"'"][^"'"'"']*['"'"'"]' |   sed -e 's/^<a href=["'"'"']//i' -e 's/["'"'"']$//i')
        echo "Using latest Polkachu blockchain snapshot, $SNAPSHOT_URL"
        aria2c --out=snapshot.tar.lz4 --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 4 -x 4 -k 1M -j 1 "$SNAPSHOT_URL"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$STRIDE_HOME"
        rm -f snapshot.tar.lz4
        ;;
      "autostake")
	SNAP_NAME=$(curl -s http://snapshots.autostake.net/stride-1/ | egrep -o ">stride-1-.*.tar.lz4" | tr -d ">" | tail -1)
	wget -O - http://snapshots.autostake.net/stride-1/$SNAP_NAME | lz4 -d | tar -xf - -C "$STRIDE_HOME"
	;;

    esac

  fi
fi
else
  echo "Found Stride data folder!"
  cd "$STRIDE_HOME/data" || exit
fi

if [[ $STRIDE_DEBUG == "true" ]]; then sleep 5000; fi
