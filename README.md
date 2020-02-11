# AirDash

Easiest file transfer from Android to Computer.

## Pitch

With the help of WebRTC through PeerJS the aim is to make it one click to share a file from an Android device to a computer.

### Deploy and build

`npm run deploy-web`
`npm run deploy-desktop`

### Choice of mime type / extensions in manifest.json
Seems like {"name": "file", "accept": ["*/*"]} matches all files on android. This is desired behavior since it is 
possible to display error for unsupported files. This is good UX since with the app open one can use 
the files form to submit the file instead. 

### Extend support to all file types

Currently only images, audio, pdf and some text formats seems to be supported by the Web Share Target API. No
official information about this were found so will post a question in the chromium forum. Hopefully the api gets 
extended to more types in the future. Otherwise this is an issue worth considering building a native app for.

Different mime type and extension combination was experimented with, but it didn't make any differnce so */* were 
chosen for the above reasons.

- .jpg, .pdf, .txt, file.csv, .mp3, .mp4, .ogg -> SUCCESS
- .apk, .dat  file -> FAIL
- Renamed image.jpg file to image.txt, image.pdf -> SUCCESS
- Renamed image.jpg to image.apk, image, image.random -> FAIL
- Created file.txt, file.apk and file -> SUCCESS

Way to reproduce issue: 
1. Share unsupported file to sender app (.apk, .dat etc)
2. App fails at request.formData() since body does not contain file
3. content-length header is only a few bytes, should be mb for apk

Future research
- Figure out fail condition - how to make txt file fail
- Write in chrome forum for potential future changes + whitelist

Relevant sources:

https://web.dev/web-share-target
https://bugs.chromium.org/p/chromium/issues/list?q=component:Blink%3EWebShare
https://wicg.github.io/web-share-target/level-2

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.
