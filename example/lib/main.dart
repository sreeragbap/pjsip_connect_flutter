import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:firebase_core/firebase_core.dart';
//import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:pjsip_connect_flutter/accounts_model.dart';
import 'package:pjsip_connect_flutter/cdrs_model.dart';
import 'package:pjsip_connect_flutter/devices_model.dart';
import 'package:pjsip_connect_flutter/logs_model.dart';
import 'package:pjsip_connect_flutter/messages_model.dart';
import 'package:pjsip_connect_flutter/network_model.dart';
import 'package:pjsip_connect_flutter/pjsip_connect.dart';
import 'package:pjsip_connect_flutter/subscriptions_model.dart';

import 'accouns_model_app.dart';
import 'account_add.dart';
import 'call_add.dart';
import 'calls_model_app.dart';
import 'home.dart';
import 'settings.dart';
import 'subscr_add.dart';
import 'subscr_model_app.dart';

//const FirebaseOptions gFCMOptions = FirebaseOptions(
//      apiKey: '...',            //Copy from `google-services.json` - `client.api_key.current_key`
//      appId: '...',             //Copy from `google-services.json` - `client.client_info.mobilesdk_app_id`
//      messagingSenderId: '...', //Copy from `google-services.json` - `project_info.project_number`
//      projectId: '...',         //Copy from `google-services.json` - `project_info.project_id`
//      storageBucket: '...'      //Copy from `google-services.json` - `project_info.storage_bucket`
//);

void main() async {
  //Wait while Firebase initialized
  //await _initializeFCM();

  //Create models
  LogsModel logsModel =
      LogsModel(true); //Set 'false' when logs won't rendering on UI
  CdrsModel cdrsModel =
      CdrsModel(); //List of recent calls (Call Details Records)

  DevicesModel devicesModel = DevicesModel(logsModel); //List of devices
  NetworkModel networkModel = NetworkModel(logsModel); //Network state details
  AppAccountsModel accountsModel =
      AppAccountsModel(logsModel); //List of accounts
  MessagesModel messagesModel =
      MessagesModel(accountsModel, logsModel); //List of messages
  AppCallsModel callsModel =
      AppCallsModel(accountsModel, logsModel, cdrsModel); //List of calls
  SubscriptionsModel subscrModel = SubscriptionsModel(
      accountsModel, createSubscrFromJson, logsModel); //List of subscriptions
  //VuMeterModel vuModel         = VuMeterModel();
  //VoiceMailModel vmModel       = VoiceMailModel(logsModel);

  //Run app
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => accountsModel),
      ChangeNotifierProvider(create: (context) => networkModel),
      ChangeNotifierProvider(create: (context) => devicesModel),
      ChangeNotifierProvider(create: (context) => messagesModel),
      ChangeNotifierProvider(create: (context) => subscrModel),
      ChangeNotifierProvider(create: (context) => callsModel),
      ChangeNotifierProvider(create: (context) => cdrsModel),
      ChangeNotifierProvider(create: (context) => logsModel),
      //ChangeNotifierProvider(create: (context) => vuModel),
      //ChangeNotifierProvider(create: (context) => vmModel),
    ],
    child: const MyApp(),
  ));
}

/*
Future<void> _initializeFCM() async {
  if(Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: gFCMOptions);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: gFCMOptions);

  //!!! Method is working in the background isolate!
  //!!! At this moment Activity may not exist or whole App could be completely stopped
  //!!! Code below initializes PjsipConnect, adds saved accounts and refreshes registration (makes app ready to receive incoming call)

  debugPrint("[!!!] Handling a background message id:'${message.messageId}' data:'${message.data}'");

  try{
    debugPrint("Initialize pjsipconnect by push notif");
    _MyAppState._initializePjsipConnect();

    debugPrint("Read and add accounts by push notif");
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String accJsonStr = prefs.getString('accounts') ?? '';
    if(accJsonStr.isNotEmpty) {
      AppAccountsModel tmpAccsModel = AppAccountsModel();
      await tmpAccsModel.loadFromJson(accJsonStr);
      tmpAccsModel.refreshRegistration();
    }
  } on Exception catch (err) {
      debugPrint('Error: ${err.toString()}');
  }
}
*/

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  static String _ringtonePath = "";

  @override
  State<MyApp> createState() => _MyAppState();

  /// Returns ringtone's path saved on device
  static String getRingtonePath() => _ringtonePath;

  /// Write ringtone file from asset to device
  void writeRingtoneAsset() async {
    _ringtonePath = await writeAssetAndGetFilePath("ringtone.mp3");
  }

  /// Write file from assest to device and returns path to it
  static Future<String> writeAssetAndGetFilePath(String assetsFileName) async {
    var homeFolder = await PjsipConnectFlutter().homeFolder();
    var filePath = '$homeFolder$assetsFileName';

    var file = File(filePath);
    var exists = file.existsSync();
    debugPrint("writeAsset: '$filePath' exists:$exists");
    if (exists) return filePath;

    final byteData = await rootBundle.load('assets/$assetsFileName');
    await file.create(recursive: true);
    file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return filePath;
  }

  /// Returns path and file name for recorded file
  static Future<String> getRecFilePathName(int callId) async {
    String dateTime = DateFormat('yyyyMMdd_HHmmss_').format(DateTime.now());
    var homeFolder = await PjsipConnectFlutter().homeFolder();
    var filePath = '$homeFolder$dateTime$callId.mp3';
    return filePath;
  }
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();

    _initializePjsipConnect(context.read<LogsModel>());
    widget
        .writeRingtoneAsset(); //after initialize PjsipConnect as uses its 'homeFolder'
    _readSavedState();

    if (Platform.isAndroid)
      _listener = AppLifecycleListener(onInactive: _onAndroidAppInactive);
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  // Listen to the app lifecycle 'Inactive' state and send calls state to service (Android only)
  void _onAndroidAppInactive() async {
    debugPrint("_onAppLifecycleInactive");
    await PjsipConnectFlutter().syncCallsState(context.read<AppCallsModel>());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: <String, WidgetBuilder>{
        CallAddPage.routeName: (BuildContext context) =>
            const CallAddPage(true),
        SettingsPage.routeName: (BuildContext context) => const SettingsPage(),
        AccountPage.routeName: (BuildContext context) => const AccountPage(),
        SubscrAddPage.routeName: (BuildContext context) =>
            const SubscrAddPage(),
      },
      home: const HomePage(),
      title: 'PjsipConnect VoIP app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
    );
  }

  static void _initializePjsipConnect([LogsModel? logsModel]) async {
    debugPrint('Initialize pjsipconnect');
    InitData iniData = InitData();
    iniData.logLevelFile = LogLevel.debug;
    iniData.logLevelIde = LogLevel.info;

    //- Set your PjsipConnect product license key after purchase (leave unset for trial evaluation) -//
    //iniData.license = const String.fromEnvironment('SIP_CONNECT_LICENSE');

    //- Uncomment if required -//
    //iniData.enableVUmeter = true;
    //iniData.singleCallMode = false;
    //iniData.tlsVerifyServer = false;
    //if(Platform.isIOS) {
    //  iniData.enableCallKit = true;
    //  iniData.enablePushKit = true; //Enable only when added PushNotif support on server side
    //  iniData.unregOnDestroy = false;
    //}
    //if(Platform.isAndroid) {
    //  iniData.use16kHzAudio = true;
    //  iniData.listenTelState = true;
    //  iniData.listenVolChange = true;
    //  iniData.serviceClassName = "com.sipconnect.voip_sdk_example.MyNotifService";
    //}
    //iniData.recordStereo=true;//Record sent/receive audio as seprate channels
    await PjsipConnectFlutter().initialize(iniData, logsModel);

    //Set video params (if required)
    //VideoData vdoData = VideoData();
    //vdoData.noCameraImgPath = await MyApp.writeAssetAndGetFilePath("noCamera.jpg");
    //vdoData.bitrateKbps = 800;
    //PjsipConnectFlutter().setVideoParams(vdoData);

    //Check the version
    //String? version = await PjsipConnectFlutter().version();
    //debugPrint("PjsipConnect version: $version");
  }

  void _readSavedState() {
    debugPrint('_readSavedState');
    SharedPreferences.getInstance().then((prefs) {
      String accJsonStr = prefs.getString('accounts') ?? '';
      String subsJsonStr = prefs.getString('subscriptions') ?? '';
      String cdrsJsonStr = prefs.getString('cdrs') ?? '';
      String msgsJsonStr = prefs.getString('msgs') ?? '';
      _loadModels(accJsonStr, cdrsJsonStr, subsJsonStr, msgsJsonStr);
    });
  }

  void _loadModels(String accJsonStr, String cdrsJsonStr, String subsJsonStr,
      String msgsJsonStr) async {
    //Accounts
    AppAccountsModel accs = context.read<AppAccountsModel>();
    accs.onSaveChanges = _saveAccountChanges;

    //Subscriptions
    SubscriptionsModel subs = context.read<SubscriptionsModel>();
    subs.onSaveChanges = _saveSubscriptionChanges;

    MessagesModel msgs = context.read<MessagesModel>();
    msgs.onSaveChanges = _saveMessagesChanges;

    //CDRs (Call Details Records)
    CdrsModel cdrs = context.read<CdrsModel>();
    cdrs.onSaveChanges = _saveCdrsChanges;

    //Load messages, than accounts, then other models
    msgs.loadFromJson(msgsJsonStr);
    await accs.loadFromJson(accJsonStr);
    subs.loadFromJson(subsJsonStr);
    cdrs.loadFromJson(cdrsJsonStr);

    //Assign contact name resolver
    context.read<AppCallsModel>().onResolveContactName = _resolveContactName;

    //Load devices
    context.read<DevicesModel>().load();
  }

  void _saveCdrsChanges(String cdrsJsonStr) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('cdrs', cdrsJsonStr);
    });
  }

  void _saveAccountChanges(String accountsJsonStr) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('accounts', accountsJsonStr);
    });
  }

  void _saveSubscriptionChanges(String subscrJsonStr) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('subscriptions', subscrJsonStr);
    });
  }

  void _saveMessagesChanges(String msgsJsonStr) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('msgs', msgsJsonStr);
    });
  }

  String _resolveContactName(String phoneNumber) {
    return ""; //TODO add own implementation
    //if(phoneNumber=="100") { return "MyFriend100"; } else
    //if(phoneNumber=="101") { return "MyFriend101"; }
    //else                  { return "";        }
  }
}

/*
//=======================================//
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pjsip_connect_flutter/accounts_model.dart';
import 'package:pjsip_connect_flutter/calls_model.dart';
import 'package:pjsip_connect_flutter/logs_model.dart';
import 'package:pjsip_connect_flutter/pjsip_connect.dart';

void main() async {
  AccountsModel accountsModel = AccountsModel();
  CallsModel callsModel = CallsModel(accountsModel);
  runApp(
    MultiProvider(providers:[
      ChangeNotifierProvider(create: (context) => accountsModel),
      ChangeNotifierProvider(create: (context) => callsModel),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializePjsipConnect();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PjsipConnect VoIP app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(body:buildBody())
    );
  }

  Widget buildBody() {
    final accounts = context.watch<AppAccountsModel>();
    final calls = context.watch<AppCallsModel>();
    return Column(children: [
      ListView.separated(
        shrinkWrap: true,
        itemCount: accounts.length,
        separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          AccountModel acc = accounts[index];
          return
            ListTile(title: Text(acc.uri, style: Theme.of(context).textTheme.titleSmall),
                subtitle: Text(acc.regText),
                tileColor: Colors.blue
            );
        },
      ),
      ElevatedButton(onPressed: _addAccount, child: const Icon(Icons.add_card)),
      const Divider(height: 1),
      ListView.separated(
        shrinkWrap: true,
        itemCount: calls.length,
        separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          CallModel call = calls[index];
          return
            ListTile(title: Text(call.nameAndExt, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(call.state.name), tileColor: Colors.amber,
              trailing: IconButton(
                onPressed: (){ call.bye(); },
                icon: const Icon(Icons.call_end))
            );
        },
      ),
      ElevatedButton(onPressed: _addCall, child: const Icon(Icons.add_call)),
      const Spacer(),
    ]);
  }

  void _initializePjsipConnect([LogsModel? logsModel]) async {
    InitData iniData = InitData();
    iniData.logLevelFile = LogLevel.info;
    PjsipConnectFlutter().initialize(iniData, logsModel);
  }

  void _addAccount() {
    AccountModel account = AccountModel();
    account.sipServer = "192.168.0.122";
    account.sipExtension = "1016";
    account.sipPassword = "12345";
    account.expireTime = 300;
    context.read<AppAccountsModel>().addAccount(account)
      .catchError(showSnackBar);
  }

  void _addCall() {
    final accounts = context.read<AppAccountsModel>();
    if(accounts.selAccountId==null) return;

    CallDestination dest = CallDestination("1012", accounts.selAccountId!, false);

    context.read<AppCallsModel>().invite(dest)
      .catchError(showSnackBar);
  }

  void showSnackBar(dynamic err) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }
}
*/
