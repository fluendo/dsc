# DSC Development Container
This is a development container for Digital Signature of Content (DSC) implementation and testing. It includes VVC VTM (VVCSoftware Video Test Model) encoder/decoder and GStreamer plugins for signing and verifying video streams with digital signatures.

The container provides a complete environment for:
- Encoding and signing video streams using VVC VTM and HM
- Decoding and verifying digitally signed streams
- Testing GStreamer DSC plugins (dscverifier and dscsigner)
- Working with both H.266/VVC and HEVC/H.265 codecs

This README contains sequential test cases to verify the DSC functionality across different encoding and verification scenarios.

## Building the container

```bash
docker build -t dsc .
```

## Running the container

```bash
# Allow local Docker containers to access the X server for GUI support; run
# 'xhost -local:docker' after use to restore the default X11 security policy.
xhost +local:docker
docker run \
    --privileged \
    --rm \
    -e XDG_RUNTIME_DIR \
    -v /run/user/$UID:/run/user/$UID \
    -v $(pwd):/app \
    -it \
    dsc bash
```

## Testing functionality
Please, follow it sequentially to ensure you have the data needed in the previous step.

## H.266 / VVC cross-validation (VTM + GStreamer)

### Make VVC VTM to encode and sign a stream
```bash
cd /root/VVCSoftware_VTM/bin
./EncoderAppStatic \
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
./DecoderAppStatic \
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
    gst-launch-1.0 filesrc location=./str.bin ! \
    h266parse ! \
    dscverifier \
        key-store-path=/root/VVCSoftware_VTM/cfg/keystore/public/ \
        trust-store-path=/root/VVCSoftware_VTM/cfg/keystore/ca/ ! \
    fakesink
```

### Make VVC VTM to encode without signing a stream
```bash
cd /root/VVCSoftware_VTM/bin
./EncoderAppStatic \
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
gst-launch-1.0 filesrc location=./str-no-dsc.bin ! \
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
./DecoderAppStatic \
    -b \
    ./str-gst-dsc.bin \
    -o \
    ./decoded_str.yuv \
    --KeyStoreDir=../cfg/keystore/public \
    --TrustStoreDir=../cfg/keystore/ca \
    --TraceFile=/tmp/sei_dsc_trace_decode.txt \
    --TraceRule="D_HEADER:poc>=0"
```

## H.265 / HEVC cross-validation (HM + GStreamer)

> This section follows the same approach as H.266: HM encode/decode and
> GStreamer sign/verify. It requires HM binaries (`TAppEncoderStatic` and
> `TAppDecoderStatic`) and HM keystore/truststore files.

### Make HM to encode and sign a stream (H.265)
```bash
cd /root/HM/bin
./TAppEncoderStatic \
    -i /app/AUD_MW_E.raw \
    -wdt 176 \
    -hgt 144 \
    -fr 30 \
    -f 30 \
    -c ../cfg/encoder_randomaccess_main.cfg \
    -c ../cfg/sei/digitally_signed_content.cfg
```

### Make HM to decode and verify an HM-signed stream (H.265)
```bash
cd /root/HM/bin
./TAppDecoderStatic \
    -b /root/HM/bin/str.bin \
    -o /root/HM/bin/decoded_str.yuv \
    --KeyStoreDir=../cfg/keystore/public \
    --TrustStoreDir=../cfg/keystore/ca
```

### Make GStreamer to verify an HM-signed stream (H.265)
```bash
GST_DEBUG="dscverifier:5" \
gst-launch-1.0 -e filesrc location=/root/HM/bin/str.bin ! \
  h265parse ! \
  dscverifier key-store-path=/root/HM/cfg/keystore/public \
              trust-store-path=/root/HM/cfg/keystore/ca \
              fail-on-verification-error=true ! \
  fakesink
```

### Make HM to encode without signing a stream (H.265)
```bash
cd /root/HM/bin
./TAppEncoderStatic \
    -i /app/AUD_MW_E.raw \
    -wdt 176 \
    -hgt 144 \
    -fr 30 \
    -f 30 \
    -c ../cfg/encoder_randomaccess_main.cfg \
    -b /root/HM/bin/str-no-dsc.bin
```

### Make GStreamer to sign an HM unsigned stream (H.265)
```bash
GST_DEBUG=dscsigner:5,h265seiinserter:5 \
gst-launch-1.0 -e \
  filesrc location=/root/HM/bin/str-no-dsc.bin ! \
  h265parse config-interval=-1 ! \
  "video/x-h265,stream-format=byte-stream,alignment=au" ! \
  dscsigner hash-method=sha256 \
      private-key-path=/root/HM/cfg/keystore/private/jvet_example_provider.key \
      public-key-uri=file:///root/HM/cfg/keystore/public/jvet_example_provider.crt \
      substream-length=30 ! \
  h265seiinserter ! \
  filesink location=/root/HM/bin/str-gst-signed.h265
```

### Make HM to decode and verify a GStreamer-signed stream (H.265)
```bash
cd /root/HM/bin
./TAppDecoderStatic \
    -b /root/HM/bin/str-gst-signed.h265 \
    -o /root/HM/bin/decoded_str_gst_signed.yuv \
    --KeyStoreDir=../cfg/keystore/public \
    --TrustStoreDir=../cfg/keystore/ca
```

### Showtime
```bash
showtime /root/UFO-DSC-Example/UFO-DSC-Example/ufo.bin
```