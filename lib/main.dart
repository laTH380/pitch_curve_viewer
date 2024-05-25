import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Audio Pitch Analyzer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _filePath;
  bool _processing = false;
  Map<String, dynamic>? _result_json;
  List<FlSpot> _pitchData = [];

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['mp3']);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      int filesize = result.files.single.size;
      // 拡張子が.mp3であるかを確認
      if (!file.path.toLowerCase().endsWith('.mp3')) {
        // .mp3でない場合はエラーメッセージを表示して終了
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Error'),
            content: Text('Selected file must be in .mp3 format.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      // 音声ファイルが1MB以下であることを確認
      if (filesize != null) {
        if (filesize > 1048576) {
          // 1MB秒以上の場合はエラーメッセージを表示して終了
          print('Debug message: Hello, world!' + filesize.toString());
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Error'),
              content: Text('Selected audio file must be 1MB or less.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      } else {
        return;
      }
      setState(() {
        _filePath = file.path;
        _processing = true;
      });
      Map<String, dynamic>? result_json = await _analyzePitch();
      if (result_json == null) {
        setState(() {
          _processing = false;
        });
        return;
      }
      make_graph_data(result_json);
      setState(() {
        _result_json = result_json;
        _processing = false;
      });
    }
  }

  // mp3データをバックエンドを送信して結果を受け取る
  Future<Map<String, dynamic>?> _analyzePitch() async {
    final uri = Uri.parse('http://127.0.0.1:5000/process');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll({
      'Content-Type': 'multipart/form-data',
    });
    request.files.add(
      await http.MultipartFile.fromPath(
        'file', // サーバー側でファイルを受け取るフィールド名
        _filePath!, // アップロードするファイルのパス
        contentType: MediaType('audio', 'mpeg'), // ファイルのコンテンツタイプ
      ),
    );
    final streamedResponse = await request.send(); //送信して待機
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      //通信が成功したときが200
      return Future.value(jsonDecode(response.body));
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Error'),
          content: Text('sever error'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }
  }

  //返されたjsonからグラフデータを作成し保存
  void make_graph_data(result_json) async {
    String data_str = result_json!["result"];
    List<String> data_list = data_str.split(",");
    List<FlSpot> pitchdata = [];
    data_list.asMap().forEach((index, value) {
      double time = index.toDouble() * (1/26000);
      double pitch = double.parse(value);
      FlSpot spot = FlSpot(time, pitch);
      pitchdata.add(spot);
    });
    setState(() {
      _pitchData = pitchdata;
    });
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Audio Pitch Analyzer'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: _pickFile,
              child: Text('Upload Audio File'),
            ),
            SizedBox(height: 20),
            _filePath != null
                ? Text('File: $_filePath')
                : Text('No file selected.'),
            SizedBox(height: 20),
            _processing == true
                ? CircularProgressIndicator()
                : _pitchData.isNotEmpty
                    ? Container(
                        height: 300,
                        padding: EdgeInsets.all(16),
                        child: LineChart(
                          LineChartData(
                            lineBarsData: [
                              LineChartBarData(
                                spots: _pitchData,
                                isCurved: true,
                                color: Colors.blue,
                                barWidth: 2,
                              )
                            ],
                            titlesData: FlTitlesData(
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              // leftTitles: AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  getTitlesWidget: (value, meta) => Text('${value.toInt().toString()}.00'),
                                  showTitles: true,
                                  interval: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Text('No pitch data available.'),
          ],
        ),
      ),
    );
  }
}
