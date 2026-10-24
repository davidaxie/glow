# Outfit photos

What `scripts/sim.sh photos` adds to the Simulators' photo libraries, for check-in in Debug Simulator builds (which use the photo picker instead of the camera).

| File | What | Source and license |
| --- | --- | --- |
| `outfit-black-jacket.jpg`, `outfit-blue-shirt.jpg`, `outfit-green-hoodie.jpg`, `outfit-red-top.jpg` | Synthetic drawings of a faceless figure (A3, D44) | Generated for this repo. No real person. |
| `outfit-real-blue-flightsuit.jpg` | A real person's outfit from the neck down, no face | Cropped from [File:2017 class of NASA astronauts in September 2019.jpg](https://commons.wikimedia.org/wiki/File:2017_class_of_NASA_astronauts_in_September_2019.jpg) (NASA, photo by Robert Markowitz). Public domain. |
| `outfit-real-white-suit.jpg` | Same | Cropped from [File:Expedition 65 inflight crew portrait (1).jpg](https://commons.wikimedia.org/wiki/File:Expedition_65_inflight_crew_portrait_(1).jpg) (NASA). Public domain. |
| `outfit-real-lightblue-suit.jpg` | Same | Cropped from the same Expedition 65 portrait. Public domain. |

**Use the `outfit-real-*` photos to check in.** The on-device pipeline asks for a retake when Vision's human detector finds nobody (spec: Private images on device, step 4), and it doesn't see the synthetic drawings as people, so those four are refused with "We couldn't find you in that photo." That's correct behavior, and `ImagingTests` checks both.

**Changes to the NASA photos.** Cropped to the neck down from Commons' 1920 px thumbnails, and the name tag on each suit pixelated, so no card fixture shows a face or a name. NASA photos are works of the US federal government (17 U.S.C. § 105); they're used only as test data and never to imply endorsement. The originals are listed in `ios/fixtures/faces/README.md`.
