import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'dart:math';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pitch Curve Viewer',
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
  List<dynamic> _pitchData = []; //FLspotデータの配列が入った配列
  List<dynamic> _pitchData_dash = []; //FLspotデータの配列が入った配列(破線用)
  double _audio_length = 0;

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
    try {
      final dio = Dio();
      final uri = 'https://pitchcurveviewer.azurewebsites.net/process';
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
        print("debug make_graph_data");
        return Future.value(response.data);
      } else {
        print("debug make_graph_data");
        return null;
      }
    } catch (e) {
      print("debug $e");
      make_dialog("Error", e.toString());
      return null;
    }
  }

  //返されたjsonからグラフデータを作成し保存
  void make_graph_data(Map<String, dynamic> result_json) async {
    print("debug make_graph_data");
    String f0_str = result_json['result'];
    List<String> f0_list = f0_str.split(",");
    String times_str = result_json['times'];
    List<String> times_list = times_str.split(",");
    double audio_length = double.parse(result_json['length']);
    List<dynamic> pitchdata = [];
    List<FlSpot> f0_part = [];
    f0_list.asMap().forEach((index, value) {
      double time = double.parse(times_list[index]);
      if (value == "nan" || value == " nan") {
        pitchdata.add(f0_part);
        f0_part = [];
      } else {
        double pitch = log(double.parse(value)) / log(2);
        FlSpot spot = FlSpot(time, pitch);
        f0_part.add(spot);
      }
    });
    pitchdata.add(f0_part);
    setState(() {
      _pitchData = pitchdata;
      _audio_length = audio_length;
    });
    return;
  }

  void make_dialog(title, content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(content),
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
            title: Text('ピッチカーブビューアー'), backgroundColor: Colors.blue[300]),
        body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
          if (MediaQuery.of(context).size.height < 20000) {
            //ウィンドウサイズの高さが20000以下
            return _buildContent();
          } else {
            // コンテンツの高さが画面サイズに収まる場合はスクロールなし←これやるの難しい
            return _buildContent();
          }
        }));
  }

  Widget _buildContent() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(
            child: Column(children: [
              SizedBox(height: 10),
              SelectableText('音声データのピッチカーブを表示します。　調声の時カタチをまねすれば同じような発音になる...かも?',
                  textAlign: TextAlign.center),
              SizedBox(height: 10),
              SelectableText('Q：mp3以外も対応して　→　A：こちらのサイトで変換してもらってください　https://convertio.co/ja/wav-mp3/',
                textAlign: TextAlign.center),
              SizedBox(height: 20),
              SelectableText('対応ファイル：1MB以下の.mp3ファイル',
                  textAlign: TextAlign.center) //,style: TextStyle(fontSize: 12)
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _pitchData.isEmpty
                        ? SizedBox(height: 100)
                        : SizedBox(height: 0),
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
                                height: 650,
                                padding: EdgeInsets.all(16),
                                child: Stack(
                                  children: [
                                    LineChart(
                                      LineChartData(
                                        minY: 6,
                                        maxY: 10,
                                        maxX: _audio_length,
                                        lineBarsData: List.generate(
                                            _pitchData.length, (index) {
                                              print(_pitchData.length);
                                              return LineChartBarData(
                                                spots: _pitchData[index],
                                                isCurved: true,
                                                color: Colors.blue,
                                                barWidth: 2,
                                              );
                                        }),
                                        gridData: FlGridData(
                                          // 背景のグリッド線の設定
                                          horizontalInterval: 1.0,
                                          verticalInterval: 0.1,
                                        ),
                                        lineTouchData: LineTouchData(
                                          // タッチ操作時の設定
                                          touchTooltipData: LineTouchTooltipData(
                                              getTooltipColor: (color) {
                                            return Color(0xFF42A5F5);
                                          }, //塗りつぶしの色
                                              getTooltipItems: (touchedSpots) {
                                            //ツールチップのテキスト情報設定
                                            return touchedSpots.map((touchedSpot) {
                                              return LineTooltipItem(
                                                  ((pow(2, touchedSpot.y) * 100)
                                                                  .floor() /
                                                              100)
                                                          .toString() +
                                                      " Hz",
                                                  TextStyle());
                                            }).toList();
                                          }),
                                        ),
                                        titlesData: FlTitlesData(
                                          topTitles: AxisTitles(
                                              sideTitles:
                                                  SideTitles(showTitles: false)),
                                          rightTitles: AxisTitles(
                                              sideTitles:
                                                  SideTitles(showTitles: false)),
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              getTitlesWidget: (value, meta) {
                                                String text;
                                                if (value == 10) {
                                                  text =
                                                      '${pow(2, value).toString()} Hz';
                                                } else if (value == 6 ||
                                                    value == 7 ||
                                                    value == 8 ||
                                                    value == 9) {
                                                  text = pow(2, value).toString();
                                                } else {
                                                  text = '';
                                                }
                                                return Text(text);
                                              },
                                              showTitles: true,
                                              interval: 1,
                                              reservedSize: 40.0,
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              getTitlesWidget: (value, meta) => Text(
                                                  '${((value * 100).floor() / 100).toString()}'),
                                              showTitles: true,
                                              interval: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ]
                                ),
                              )
                            : Text('No pitch data available.'),
                    _pitchData.isEmpty
                        ? SizedBox(height: 100)
                        : SizedBox(height: 0),
                    SelectableText(
                        '© 2024 laTH　contact→https://lath-memorandum.netlify.app/profiel',
                        textAlign:
                            TextAlign.center //,style: TextStyle(fontSize: 12)
                        )
                  ],
                ),
              ),
            ),
          )
        ]);
  }
}
