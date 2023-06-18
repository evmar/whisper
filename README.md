# whisper

Playing around with [OpenAI Whisper](https://github.com/openai/whisper).

This program records audio from my laptop mic using
[miniaudio](https://miniaud.io/) and transcribes it using
[whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Running

It's probably hard to run on your own computer. Needs `libwhisper.a` put in the
right directory as well as a ggml model.

## Notes to self

To get Zig to successfully parse `whisper.h` I had to comment out the definition
of `whisper_free_params`.
