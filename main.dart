import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// ==========================================
// 1. قاعدة البيانات المحلية (DATABASE HELPER)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cash_elbalad.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone_number TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        line_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        sender TEXT,
        date TEXT NOT NULL,
        FOREIGN KEY (line_id) REFERENCES lines (id)
      )
    ''');
  }

  Future<int> insertLine(String name, String phoneNumber) async {
    final db = await instance.database;
    return await db.insert('lines', {'name': name, 'phone_number': phoneNumber});
  }

  Future<int> insertTransaction(int lineId, String type, double amount, String sender) async {
    final db = await instance.database;
    return await db.insert('transactions', {
      'line_id': lineId,
      'type': type,
      'amount': amount,
      'sender': sender,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getLinesSummary() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        l.id, 
        l.name, 
        l.phone_number,
        COALESCE(SUM(CASE WHEN t.type = 'IN' THEN t.amount ELSE 0 END), 0) as total_in,
        COALESCE(SUM(CASE WHEN t.type = 'OUT' THEN t.amount ELSE 0 END), 0) as total_out,
        (COALESCE(SUM(CASE WHEN t.type = 'IN' THEN t.amount ELSE 0 END), 0) - 
         COALESCE(SUM(CASE WHEN t.type = 'OUT' THEN t.amount ELSE 0 END), 0)) as balance
      FROM lines l
      LEFT JOIN transactions t ON l.id = t.line_id
      GROUP BY l.id
    ''');
  }
}

// ==========================================
// 2. معالجة الرسائل النصية في الخلفية (SMS HANDLER)
// ==========================================
@pragma('vm:entry-point')
void backGroundMessageHandler(SmsMessage message) async {
  _processSms(message);
}

void _processSms(SmsMessage message) async {
  String? body = message.body;
  if (body == null) return;

  if (body.contains("تم استلام") || body.contains("إيداع") || body.contains("تم تحويل")) {
    RegExp regExp = RegExp(r'(\d+(\.\d+)?)');
    var match = regExp.firstMatch(body);

    if (match != null) {
      double amount = double.parse(match.group(0)!);
      String sender = message.address ?? "مجهول";
      await DatabaseHelper.instance.insertTransaction(1, 'IN', amount, sender);
    }
  }
}

// ==========================================
// 3. التطبيق الرئيسي والواجهات (FLUTTER UI)
// ==========================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CashElbaladApp());
}

class CashElbaladApp extends StatelessWidget {
  const CashElbaladApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'كاش البلد',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
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
  List<Map<String, dynamic>> lines = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initSmsListener();
    _loadData();
  }

  Future<void> _requestPermissions() async {
    await Permission.sms.request();
  }

  void _initSmsListener() {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        _processSms(message);
        _loadData();
      },
      onBackgroundMessage: backGroundMessageHandler,
    );
  }

  Future<void> _loadData() async {
    final data = await DatabaseHelper.instance.getLinesSummary();
    setState(() {
      lines = data;
    });
  }

  void _showAddLineDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة خط جديد', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم الخط (مثل: فودافون 1)'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'رقم التليفون'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                await DatabaseHelper.instance.insertLine(
                  nameController.text,
                  phoneController.text,
                );
                nameController.clear();
                phoneController.clear();
                if (mounted) Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كاش البلد 📱'),
        centerTitle: true,
      ),
      body: lines.isEmpty
          ? const Center(
              child: Text(
                'لا يوجد خطوط مسجلة بعد، اضغط + لإضافة خط',
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line['name'],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text('الرقم: ${line['phone_number']}'),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '📥 الوارد: ${line['total_in']} ج.م',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '📤 الصادر: ${line['total_out']} ج.م',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💵 المتبقي (الرصيد): ${line['balance']} ج.م',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLineDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
