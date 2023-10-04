import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info/device_info.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:mysql1/mysql1.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';

import 'package:workmanager/workmanager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); //後台執行
  BackgroundTask.registerBackgroundTask(); //後台執行
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Position Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'GPS定位 戶外限定'),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Position? _currentPosition;
  String? _currentAddress, _oldLocationMessage, _sc;
  String _locationMessage = "";
  String serialNumber = "";
  int _count = 0;
  Timer? _timer;
  int? num;
  TextEditingController nameController = TextEditingController();
  bool? _rememberAccount;
  @override
  void initState() {
    super.initState();
    getDeviceInfo();
    _getCurrentLocation();
    myTimer();
    _loadCheckbox();
    _loadAccount();
  }

  @override
  void dispose() {
    super.dispose();
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    Wakelock.enable();
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
              image: AssetImage("images/taiwan.png"), fit: BoxFit.fill),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_currentAddress != null && _locationMessage != "")
              Text('位址:$_currentAddress',
                  style: const TextStyle(fontSize: 16, color: Colors.red)),
            Text('經緯度:$_locationMessage',
                style: const TextStyle(fontSize: 16, color: Colors.red)),
            Text(
              '手機序號：$serialNumber',
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
            TextField(
              decoration: const InputDecoration(
                  labelText: '姓名',
                  labelStyle: TextStyle(color: Colors.red),
                  fillColor: Colors.red,
                  iconColor: Colors.red,
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.red)),
                  hintText: '打卡人員',
                  prefixIconColor: Colors.red,
                  hintStyle: TextStyle(color: Colors.red),
                  prefixIcon: Icon(Icons.person)),
              controller: nameController,
            ),
            CheckboxListTile(
              value: _rememberAccount ?? false,
              onChanged: (value) {
                setState(() {
                  _rememberAccount = value;
                });
                if (value == true) {
                  _saveCheckout(value);
                  _saveAccount(nameController.text);
                } else {
                  _saveAccount("");
                  _saveCheckout(false);
                }
              },
              activeColor: Colors.red,
              title: const Text(
                '記住我的名字',
                style: TextStyle(color: Colors.red),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  void getDeviceInfo() async {
    DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
      setState(() {
        serialNumber = androidInfo.androidId;
      });
    } else if (Platform.isIOS) {
      IosDeviceInfo isoInfo = await deviceInfoPlugin.iosInfo;
      setState(() {
        serialNumber = isoInfo.identifierForVendor;
      });
    }
  }

  void _getCurrentLocation() async {
    print(_oldLocationMessage);
    Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            forceAndroidLocationManager: true)
        .then((Position position) {
      setState(() {
        _currentPosition = position;
        _locationMessage =
            //'Latitude:${position.latitude}, Longitude:${position.longitude}';
            '${position.latitude},${position.longitude}';
        if (_oldLocationMessage != _locationMessage) {
          positionData('1');
          _oldLocationMessage = _locationMessage;
        }
        _getAddressFromLatLng();
      });
    }).catchError((e) {
      // ignore: avoid_print
      print(e);
    });
  }

  void myTimer() async {
    _count = 0;
    _timer = Timer.periodic(const Duration(microseconds: 1000), (t) {
      _count++;
      print(_count++);
      // print(_count);
      if (_count == 300000) {
        _count = 0;
        _getCurrentLocation();
      }
      setState(() {
        num = _count;
      });
    });
  }

  void _loadCheckbox() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberAccount = (prefs.getBool('remember_account') ?? false);
    });
  }

  void _loadAccount() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = (prefs.getString('account') ?? " ");
    });
  }

  void _saveCheckout(value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_account', value);
  }

  void _saveAccount(account) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('account', account);
  }

  void positionData(String s) async {
    final conn = await MySqlConnection.connect(ConnectionSettings(
        host: 'taimaligebi.ddns.net',
        port: 3306,
        user: 'leo5988',
        db: 'HtmlTest',
        password: 'g5248112'));

    switch (s) {
      case '1':
        var result = await conn.query(
            'insert into peoplePosition(locationName, phoneSerialNumber,currentAddress,locationMessage)values(?,?,?,?)', //資料寫入資料庫
            [
              nameController.text,
              serialNumber,
              _currentAddress,
              _locationMessage
            ]);
        await conn.close();
        break;
    }
  }

  void _getAddressFromLatLng() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude, _currentPosition!.longitude);

      Placemark place = placemarks[0];

      setState(() {
        _currentAddress = "${place.street}"; //回傳地址明細
      });
    } catch (e) {
      print(e);
    }
  }
}

class BackgroundTask {
  static callbackDispatcher() {
    Workmanager().executeTask((task, inputData) {
      // 在这里编写后台任务的逻辑
      // 根据传入的任务类型（task）执行相应的操作
      // 使用inputData获取传入的数据
      //_MyHomePageState().initState();
      _MyHomePageState()._getCurrentLocation();
      print('test');
      return Future.value(true); // 表示任务执行成功
    });
  }

  static void registerBackgroundTask() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // 是否在调试模式下运行任务
    );

    Workmanager().registerPeriodicTask(
      "1", // 唯一的任务名称
      "backgroundTask", // 任务标识符
      frequency: const Duration(minutes: 15), // 任务执行的频率
      constraints: Constraints(
        networkType: NetworkType.connected, // 任务的网络连接要求
      ),
      initialDelay: const Duration(minutes: 5), // 初始延迟执行任务的时间
    );
  }
}
