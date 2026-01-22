# DSC Development Container
This is a development container for Digital Signature of Content (DSC) implementation and testing. It includes VVC VTM (VVCSoftware Video Test Model) encoder/decoder and GStreamer plugins for signing and verifying video streams with digital signatures.

The container provides a complete environment for:
- Encoding and signing video streams using VVC VTM
- Decoding and verifying digitally signed streams
- Testing GStreamer DSC plugins (dscverifier and dscsigner)
- Working with both H.266/VVC and H.264 codecs

This README contains sequential test cases to verify the DSC functionality across different encoding and verification scenarios.

## Building the container

```bash
docker build -t dsc .
```

## Running the container

```bash
docker run \
    --privileged \
    -e DISPLAY \
    --rm \
    -v $(pwd):/app \
    -it \
    dsc bash
```

## Testing functionality
Please, follow it sequentially to ensure you have the data needed in the previous step.

### Make VVC VTM to encode and sign a stream
```bash
cd /root/VVCSoftware_VTM/bin
./EncoderAppStaticd \
    -i \
    /app/AUD_MW_E.raw \
    -wdt \
    176 \
    -hgt \
    144 \
    -fr \
    30 \
    -f \
    5 \
    -c \
    ../cfg/encoder_randomaccess_vtm.cfg \
    -c \
    ../cfg/sei_vui/digitally_signed_content.cfg  
```

### Make VVC VTM to decode and verify a stream
```bash
cd /root/VVCSoftware_VTM/bin
./DecoderAppStaticd \
    -b \
    ./str.bin \
    -o \
    ./decoded_str.yuv \
    --KeyStoreDir=../cfg/keystore/public \
    --TrustStoreDir=../cfg/keystore/ca \
    --TraceFile=/tmp/sei_dsc_trace_decode.txt \
    --TraceRule="D_HEADER:poc>=0"
```

### Make GStreamer to verify a stream
```bash
GST_DEBUG="dscverifier:4" \
    gst-launch-1.0 filesrc location=/root/VVCSoftware_VTM/bin/str.bin ! \
    h266parse ! \
    dscverifier key-store-path=/root/VVCSoftware_VTM/cfg/keystore/public/ ! \
    fakesink
```

### Make VVC VTM to encode without signing a stream
```bash
cd /root/VVCSoftware_VTM/bin
./EncoderAppStaticd \
    -i \
    /app/AUD_MW_E.raw \
    -wdt \
    176 \
    -hgt \
    144 \
    -fr \
    30 \
    -f \
    5 \
    -c \
    ../cfg/encoder_randomaccess_vtm.cfg \
    -b \
    str-no-dsc.bin
```

### Make GStreamer to sign a VVC VTM stream
```bash
cd /root/VVCSoftware_VTM/bin
gst-launch-1.0 filesrc location= ./str-no-dsc.bin ! \
    h266parse ! \
    "video/x-h266,stream-format=byte-stream" ! \
    dscsigner private-key-path=/root/VVCSoftware_VTM/cfg/keystore/private/jvet_example_provider.key \
            public-key-uri=file://somepath/jvet_example_provider.crt \
            substream-length=5 ! \
    h266parse ! \
    "video/x-h266,stream-format=byte-stream,alignment=au" ! \
    h266seiinserter ! \
    h266parse ! \
    "video/x-h266,stream-format=byte-stream,alignment=nal" ! \
    filesink location= ./str-gst-dsc.bin
```

### Make VVC VTM to decode and verify GStreamer signed stream
```bash
cd /root/VVCSoftware_VTM/bin
./DecoderAppStaticd \
    -b \
    ./str-gst-dsc.bin \
    -o \
    ./decoded_str.yuv \
    --KeyStoreDir=../cfg/keystore/public \
    --TrustStoreDir=../cfg/keystore/ca \
    --TraceFile=/tmp/sei_dsc_trace_decode.txt \
    --TraceRule="D_HEADER:poc>=0"
```

### Make GStreamer to sign and verify a H.264 an arbitrary stream
```bash
GST_DEBUG="dscverifier:4"  \
gst-launch-1.0 videotestsrc num-buffers=15 ! \
  x264enc key-int-max=5 ! h264parse ! \
  dscsigner private-key-path=/root/VVCSoftware_VTM/cfg/keystore/private/jvet_example_provider.key \
            public-key-uri=file://somepath/jvet_example_provider.crt \
            substream-length=5 ! \
  dscverifier key-store-path=/root/VVCSoftware_VTM/cfg/keystore/public/ ! \
  fakesink
```