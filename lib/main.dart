import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(const CashElbaladApp());
}

class CashElbaladApp extends StatelessWidget {
  const CashElbaladApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cash Elbalad',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Telephony telephony = Telephony.instance;
  List<SmsMessage> messages = [];

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();

    if (statuses[Permission.sms]!.isGranted) {
      fetchSms();
    }
  }

  void fetchSms() async {
    List<SmsMessage> mgs = await telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.BODY).like("%Cash%"),
    );
    setState(() {
      messages = mgs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Elbalad - كاش البلد'),
      ),
      body: ListView.builder(
        itemCount: messages.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(messages[index].address ?? "Unknown"),
            subtitle: Text(messages[index].body ?? ""),
          );
        },
      ),
    );
  }
}
