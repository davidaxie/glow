# Face fixtures

Photos with clearly visible faces, for the on-device blur tests (B3, `ImagingTests`): every face in them must come out blurred, and the upload must carry no metadata. Not used anywhere in the app or shown to anyone.

All five are **public domain**: official NASA photographs, works of the United States federal government (17 U.S.C. § 105), as marked on their Wikimedia Commons pages. The people in them are NASA astronauts photographed for official, public portraits, not private individuals. Following NASA's media guidelines, they're used only as test data and never to imply endorsement.

| File | Faces | Source (Wikimedia Commons) | Original | License |
| --- | --- | --- | --- | --- |
| `face-portrait-fincke.jpg` | 1 | [File:Michael Fincke 2019.jpg](https://commons.wikimedia.org/wiki/File:Michael_Fincke_2019.jpg) | NASA, photo by Robert Markowitz, [flickr.com/photos/nasa2explore/47086123141](https://www.flickr.com/photos/nasa2explore/47086123141/) | Public domain (NASA) |
| `face-portrait-mann.jpg` | 1 | [File:Nicole Mann portrait with Boeing flight suit.jpg](https://commons.wikimedia.org/wiki/File:Nicole_Mann_portrait_with_Boeing_flight_suit.jpg) | NASA, photo by Robert Markowitz, [images.nasa.gov jsc2019e026848](https://images.nasa.gov/details-jsc2019e026848_alt) | Public domain (NASA) |
| `faces-group-of-3.jpg` | 6 (the file name undercounts: the Expedition 49 portrait has two crews of three) | [File:Expedition 49 crew portrait (2).jpg](https://commons.wikimedia.org/wiki/File:Expedition_49_crew_portrait_(2).jpg) | NASA, photo by Robert Markowitz, [flickr.com/photos/nasa2explore/25746246412](https://www.flickr.com/photos/nasa2explore/25746246412/) | Public domain (NASA) |
| `faces-group-inflight.jpg` | 7 | [File:Expedition 65 inflight crew portrait (1).jpg](https://commons.wikimedia.org/wiki/File:Expedition_65_inflight_crew_portrait_(1).jpg) | NASA, [flickr.com/photos/nasa2explore/51315544066](https://www.flickr.com/photos/nasa2explore/51315544066/) | Public domain (NASA) |
| `faces-group-large.jpg` | 13 | [File:2017 class of NASA astronauts in September 2019.jpg](https://commons.wikimedia.org/wiki/File:2017_class_of_NASA_astronauts_in_September_2019.jpg) | NASA, photo by Robert Markowitz, [flickr.com/photos/nasa2explore/49229446153](https://www.flickr.com/photos/nasa2explore/49229446153/) | Public domain (NASA) |

**Changes from the originals.** Downloaded as Commons' 1920 px thumbnails on 2026-10-24, then scaled to 1280 px on the long side and re-encoded at JPEG quality 72 with `sips`. The EXIF blocks Commons kept (image descriptions, resolution) are left in on purpose: the tests check that the pipeline strips them.

To add one: use only photos that are public domain or CC0 (or of people who agreed to be test fixtures), never photos of private individuals taken from social media, and add a row here with its source page and license.
