import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:device_info/device_info.dart';
import 'package:recycle_it/animation.dart';

import 'credentials.dart';

import 'package:mongo_dart/mongo_dart.dart' as mongo;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:recase/recase.dart';
import 'package:progress_dialog/progress_dialog.dart';

//potentially have negative keywords
//offer user an option 'did we get this correct'
//if not add all the labels to  a 'risk' filter

var firstCamera;

var recyclables = [
  "plastic bottle",
  "plastic",
  "paper",
  "glass",
  "cardboard",
  "packaging",
  "cup",
  "bottle",
  "bottled",
  "can",
  "aerosol",
  "deoderant",
  "aluminium",
  "foil",
  "puree",
  "polythene",
  "film",
  "wrap",
  "newspaper",
  "magazine",
  "envelope",
  "carrier",
  "catalogue",
  "phone directory",
  "drinkware",


  "interior design",
  "room"
];

var negativeKeywords = ["reusable"];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: HomePage(),
    ),
  );
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Recycle It"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Home page',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => TakePictureScreen(camera: firstCamera)),
          );
        },
        tooltip: 'Camera',
        child: Icon(Icons.camera_alt),
      ),
    );
  }
}

class TakePictureScreen extends StatefulWidget {
  final CameraDescription camera;

  const TakePictureScreen({
    Key key,
    @required this.camera,
  }) : super(key: key);

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  CameraController _controller;
  Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.ultraHigh);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 35.0),
        child: FloatingActionButton(
          onPressed: () async {
            try {
              await _initializeControllerFuture;

              final path = join(
                (await getTemporaryDirectory()).path,
                '${DateTime.now()}.png',
              );

              await _controller.takePicture(path);

              final bytes = File(path).readAsBytesSync();
              String img64 = base64Encode(bytes);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RecyclePage(base64img: img64),
                ),
              );
            } catch (e) {
              print(e);
            }
          },
          tooltip: 'Camera',
          child: Icon(Icons.camera),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class RecyclePage extends StatefulWidget {
  final String base64img;

  const RecyclePage({Key key, this.base64img}) : super(key: key);

  @override
  _RecyclePageState createState() => _RecyclePageState();
}

class _RecyclePageState extends State<RecyclePage> {
  Map data;
  List recyclableData = [];
  int returnAddInfo = 0;

  Future request() async {
    String url = 'https://vision.googleapis.com/v1/images:annotate?key=' + key;

    final body = jsonEncode({
      "requests": [
        {
          "image": {"content": "${widget.base64img}"},
          "features": [
            {"type": "LABEL_DETECTION", "maxResults": 25}
          ]
        }
      ]
    });

    final response = await http.post(url,
        headers: {
          "accept-encoding": "appplication/json",
          "Content-Type": "'application/json'"
        },
        body: body);

    if (response.statusCode == 200) {
      data = json.decode(response.body);

      print(response.body);

      List temp = [];
      var addInfo;

      if (data['responses'][0]['labelAnnotations'].length != null) {
        for (int i = 0;
            i < data['responses'][0]['labelAnnotations'].length;
            i++) {
          if (recyclables.contains(data['responses'][0]['labelAnnotations'][i]
                  ['description']
              .toLowerCase())) {
            temp.add(data['responses'][0]['labelAnnotations'][i]['description']
                    .toLowerCase());
          }
        }
        for (int i = 0;
            i < data['responses'][0]['labelAnnotations'].length;
            i++) {
          if (negativeKeywords.contains(data['responses'][0]['labelAnnotations']
                  [i]['description']
              .toLowerCase())) {
            //hit a negative so clear string
            temp = [];
          }
        }
        if (temp != []) {
          DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
          var id = '';
          if (Platform.isAndroid) {
            AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
            id =androidInfo.androidId;
            print('Running on ${androidInfo.androidId}');
          } else if (Platform.isIOS) {
            IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
            id = iosInfo.identifierForVendor;

            print('Running on ${iosInfo.identifierForVendor}');
          }

          mongo.Db db = new mongo.Db(dburl);
          await db.open();

          var coll = db.collection('data');
          await coll.insert({
            'uuid': id,
            'kws': temp,
            'created_at': new DateTime.now()
          });

          addInfo = await coll.count({
            'uuid': id
          });
        } else {
          print('dont insert unrecyclable doc');
        }
      }

      while (recyclableData == []) {
        return Center(child: CircularProgressIndicator());
      }

      setState(() {
        if (temp == []) {
          recyclableData = ['No matches'];
        } else {
          recyclableData = temp;
          returnAddInfo = addInfo;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    request();
  }

  @override
  Widget build(BuildContext context) {
    if (recyclableData.length > 0) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Recycle It"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShowUp(
                child: Text(
                  recyclableData[0].toString().titleCase,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 28
                  ),
                ),
                delay: 750,
              ),
              for (var i = 1; i < recyclableData.length; i++)
                ShowUp(
                  child: Text(
                    recyclableData[i].toString().titleCase,
                    style: TextStyle(
                      fontSize: 20
                    ),
                  ),
                  delay: 1250, 
                ),
              ShowUp(
                child: Text(
                  "Items Scanned: ${returnAddInfo.toString()}",
                ),
                delay: 1750,
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => TakePictureScreen(camera: firstCamera)),
            );
          },
          tooltip: 'Camera',
          child: Icon(Icons.camera_alt),
        ),
      );
    } else {
      return Center(
        child: Icon(
          Icons.check,
          color: Colors.green,
          size: 100,
        )
      );
    }
  }
}
