import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';

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
  String? _filename;
  bool _processing = false;
  Map<String, dynamic>? _result_json;
  List<FlSpot> _pitchData = [];

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true, type: FileType.custom, allowedExtensions: ['mp3']);
    if (result != null) {
      if (result.files.single.bytes != null) {
        PlatformFile file = result.files.single;
        Uint8List fileBytes = file.bytes!;
        final filename = file.name;
        int filesize = file.size;
        // 拡張子が.mp3であるかを確認
        if (!filename.toLowerCase().endsWith('.mp3')) {
          // .mp3でない場合はエラーメッセージを表示して終了
          make_dialog("Error", "mp3ファイルを選択してください");
          return;
        }
        // 音声ファイルが1MB以下であることを確認
        if (filesize > 1048576) {
          // 1MB秒以上の場合はエラーメッセージを表示して終了
          make_dialog("Error", "1MB以下のファイルを選択してください");
          return;
        }
        setState(() {
          _filename = filename;
          _processing = true;
        });
        Map<String, dynamic>? result_json = await _analyzePitch(fileBytes);
        if (result_json == null || result_json["error"] != null) {
          make_dialog("Error", "サーバでの処理に失敗しました");
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
      } else {
        make_dialog("Error", "ファイルのアップロードに失敗しました");
      }
    } else {
      make_dialog("Error", "ファイルのアップロードに失敗しました");
    }
  }

  // mp3データをバックエンドを送信して結果を受け取る
  Future<Map<String, dynamic>?> _analyzePitch(Uint8List filebytes) async {
    // try{
      final dio = Dio();
      final uri = 'http://127.0.0.1:5000/process';

      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          filebytes,
          filename: 'audio.mpeg',
          contentType: MediaType('audio', 'mpeg'),
        ),
      });

      final response = await dio.post(uri, data: formData);

      if (response.statusCode == 200) {
        //通信が成功したときが200
        return Future.value(response.data);
      } else {
        return null;
      }
    // } catch (e) {
    //   make_dialog("Error", e.toString());
    //   return null;
    // }
  }

  //返されたjsonからグラフデータを作成し保存
  void make_graph_data(Map<String, dynamic> result_json) async {
    result_json.forEach((key, value) {
      print('debug: $key: $value');
      // valueの型を確認する
      print('Value type: ${value.runtimeType}');
    });
    String data_str = result_json['result'];
    List<String> data_list = data_str.split(",");
    List<FlSpot> pitchdata = [];
    data_list.asMap().forEach((index, value) {
      double time = index.toDouble() * (1 / 26000);
      double pitch = double.parse(value);
      FlSpot spot = FlSpot(time, pitch);
      pitchdata.add(spot);
    });
    setState(() {
      _pitchData = pitchdata;
    });
    return;
  }

  void make_dialog(title, content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
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
            _filename != null
                ? Text('File: $_filename')
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
                              topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              // leftTitles: AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  getTitlesWidget: (value, meta) =>
                                      Text('${value.toInt().toString()}.00'),
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
