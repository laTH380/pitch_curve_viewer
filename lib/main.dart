import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'dart:math';

// アプリケーションの定数
class AppConstants {
  static const String appTitle = 'Pitch Curve Viewer';

  // デプロイ環境とローカル環境の切り替え用
  // ローカルテスト時は下記のコメントアウトを入れ替えてください
  // static const String backendUrl = 'https://pitchcurveviewer.azurewebsites.net/process';
  static const String backendUrl = 'http://localhost:5000/process';

  static const int maxFileSizeMB = 10;
  static const int maxFileSizeBytes = 10485760; // 10MB
  static const List<String> allowedExtensions = ['mp3'];

  // グラフの設定
  static const double minPitchY = 6.0;
  static const double maxPitchY = 10.0;
  static const double chartHeight = 650.0;
}

void main() {
  runApp(PitchCurveApp());
}

/// メインアプリケーション
class PitchCurveApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PitchCurveScreen(),
    );
  }
}

/// ピッチカーブ表示画面
class PitchCurveScreen extends StatefulWidget {
  @override
  _PitchCurveScreenState createState() => _PitchCurveScreenState();
}

class _PitchCurveScreenState extends State<PitchCurveScreen> {
  // アプリケーションの状態管理
  String? selectedFileName;
  bool isProcessing = false;
  List<List<FlSpot>> pitchDataList = []; // ピッチデータのリスト
  double audioLength = 0.0;

  /// ファイル選択処理
  Future<void> selectAndProcessFile() async {
    try {
      // ファイル選択
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: AppConstants.allowedExtensions,
      );

      // ユーザーがキャンセルした場合は何もしない（エラーを出さない）
      if (result == null || result.files.isEmpty) {
        print("ファイル選択がキャンセルされました");
        return;
      }

      final PlatformFile file = result.files.single;

      // ファイル検証
      if (!_validateFile(file)) {
        return;
      }

      // 処理開始
      setState(() {
        selectedFileName = file.name;
        isProcessing = true;
      });

      // バックエンドでピッチ解析
      final Map<String, dynamic>? analysisResult =
          await _sendToBackend(file.bytes!);

      if (analysisResult == null || analysisResult["error"] != null) {
        showErrorDialog("サーバでの処理に失敗しました");
        return;
      }

      // グラフデータ作成
      _createGraphData(analysisResult);
    } catch (e) {
      // 詳細なエラーハンドリング
      String errorMessage;
      if (e.toString().contains('DioException') ||
          e.toString().contains('network')) {
        errorMessage = "サーバーとの通信に失敗しました。バックエンドが起動しているか確認してください。";
      } else if (e.toString().contains('format') ||
          e.toString().contains('audio')) {
        errorMessage = "音声ファイルの解析に失敗しました。正しいMP3ファイルか確認してください。";
      } else if (e.toString().contains('timeout')) {
        errorMessage = "処理がタイムアウトしました。ファイルサイズを小さくしてお試しください。";
      } else {
        errorMessage = "エラーが発生しました: ${e.toString().substring(0, 100)}...";
      }

      print("詳細エラー: $e");
      showErrorDialog(errorMessage);
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  /// ファイルのバリデーション
  bool _validateFile(PlatformFile file) {
    // 拡張子チェック
    if (!file.name.toLowerCase().endsWith('.mp3')) {
      showErrorDialog("mp3ファイルを選択してください");
      return false;
    }

    // ファイルサイズチェック
    if (file.size > AppConstants.maxFileSizeBytes) {
      showErrorDialog("${AppConstants.maxFileSizeMB}MB以下のファイルを選択してください");
      return false;
    }

    // ファイルデータの存在チェック
    if (file.bytes == null) {
      showErrorDialog("ファイルの読み込みに失敗しました");
      return false;
    }

    return true;
  }

  /// バックエンドにファイルを送信してピッチ解析を実行
  Future<Map<String, dynamic>?> _sendToBackend(Uint8List fileBytes) async {
    try {
      final dio = Dio();

      // タイムアウト設定を追加（サーバー起動時間を考慮）
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 120); // 処理時間を考慮

      // フォームデータの作成
      final FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: 'audio.mpeg',
          contentType: MediaType('audio', 'mpeg'),
        ),
      });

      print("バックエンドに送信中...");

      // バックエンドに送信
      final response = await dio.post(AppConstants.backendUrl, data: formData);

      if (response.statusCode == 200) {
        print("ピッチ解析が完了しました");
        return response.data;
      } else {
        print("バックエンドエラー: ${response.statusCode}");
        _handleHttpError(response.statusCode);
        return null;
      }
    } on DioException catch (e) {
      print("Dio通信エラー: ${e.type} - ${e.message}");
      _handleDioError(e);
      return null;
    } catch (e) {
      print("予期しないエラー: $e");
      showErrorDialog("予期しないエラーが発生しました: $e");
      return null;
    }
  }

  /// HTTPステータスコードに応じたエラーハンドリング
  void _handleHttpError(int? statusCode) {
    switch (statusCode) {
      case 503:
        showErrorDialog("サーバーが一時的に利用できません。\n"
            "サーバーの起動に時間がかかっている可能性があります。\n"
            "1-2分後に再度お試しください。");
        break;
      case 500:
        showErrorDialog("サーバー内部エラーが発生しました。しばらく時間をおいて再度お試しください。");
        break;
      case 413:
        showErrorDialog("ファイルサイズが大きすぎます。1MB以下のファイルを選択してください。");
        break;
      default:
        showErrorDialog("サーバーエラーが発生しました。(エラーコード: $statusCode)");
        break;
    }
  }

  /// DioExceptionの種類に応じたエラーハンドリング
  void _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        showErrorDialog("接続がタイムアウトしました。\n"
            "サーバーの起動に時間がかかっている可能性があります。\n"
            "しばらく時間をおいて再度お試しください。");
        break;
      case DioExceptionType.receiveTimeout:
        showErrorDialog("処理がタイムアウトしました。\n"
            "ファイルサイズが大きい、またはサーバーが混雑している可能性があります。");
        break;
      case DioExceptionType.connectionError:
        showErrorDialog("サーバーに接続できません。\n"
            "インターネット接続を確認するか、\n"
            "サーバーが起動するまでしばらくお待ちください。");
        break;
      case DioExceptionType.badResponse:
        showErrorDialog("サーバーから無効な応答を受信しました。");
        break;
      default:
        showErrorDialog("通信エラーが発生しました: ${e.message}");
        break;
    }
  }

  /// バックエンドから返されたJSONデータからグラフ用データを作成
  void _createGraphData(Map<String, dynamic> analysisResult) {
    try {
      print("グラフデータを作成中...");

      // バックエンドからのデータを取得
      final String pitchDataString = analysisResult['result'] ?? '';
      final String timeDataString = analysisResult['times'] ?? '';
      final String lengthString = analysisResult['length'] ?? '0';

      if (pitchDataString.isEmpty || timeDataString.isEmpty) {
        showErrorDialog("解析結果が空です");
        return;
      }

      // カンマ区切りの文字列をリストに変換
      final List<String> pitchValues = pitchDataString.split(",");
      final List<String> timeValues = timeDataString.split(",");
      final double audioLen = double.tryParse(lengthString) ?? 0.0;

      // グラフ用のデータ構造を作成
      List<List<FlSpot>> graphData = [];
      List<FlSpot> currentSegment = [];

      // 各時刻のピッチデータを処理
      for (int i = 0; i < pitchValues.length; i++) {
        if (i >= timeValues.length) break;

        final double time = double.tryParse(timeValues[i]) ?? 0.0;
        final String pitchValue = pitchValues[i].trim();

        // ピッチが検出されない部分（"nan"）の処理
        if (pitchValue == "nan" || pitchValue == " nan") {
          if (currentSegment.isNotEmpty) {
            graphData.add(List.from(currentSegment));
            currentSegment.clear();
          }
        } else {
          // 有効なピッチ値の場合、対数スケールに変換
          final double? pitchHz = double.tryParse(pitchValue);
          if (pitchHz != null && pitchHz > 0) {
            final double pitchLog = log(pitchHz) / log(2); // log2変換
            currentSegment.add(FlSpot(time, pitchLog));
          }
        }
      }

      // 最後のセグメントを追加
      if (currentSegment.isNotEmpty) {
        graphData.add(currentSegment);
      }

      // 状態を更新
      setState(() {
        pitchDataList = graphData;
        audioLength = audioLen;
      });

      print("グラフデータの作成が完了しました - セグメント数: ${graphData.length}");
    } catch (e) {
      print("グラフデータ作成エラー: $e");
      showErrorDialog("グラフデータの作成に失敗しました: $e");
    }
  }

  /// エラーダイアログを表示
  void showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("エラー"),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pitch Curve Viewer'),
        backgroundColor: const Color(0xFFeedec8),
      ),
      backgroundColor: const Color(0xFFfcf8f3),
      body: _buildMainContent(),
    );
  }

  /// メインコンテンツの構築
  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderSection(),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // グラフが無い時のスペース調整
                  if (pitchDataList.isEmpty) const SizedBox(height: 100),

                  _buildFileUploadButton(),
                  const SizedBox(height: 20),

                  _buildFileStatus(),
                  const SizedBox(height: 20),

                  _buildProcessingOrChart(),

                  // グラフが無い時のスペース調整
                  if (pitchDataList.isEmpty) const SizedBox(height: 100),

                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ヘッダー説明セクション
  Widget _buildHeaderSection() {
    return const Center(
      child: Column(
        children: [
          SizedBox(height: 10),
          SelectableText(
            '音声データのピッチカーブを表示します。調声の時カタチをまねすれば同じような発音になる...かも?',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10),
          SelectableText(
            'Q：mp3以外も対応して　→　A：こちらのサイトで変換してもらってください　https://convertio.co/ja/wav-mp3/',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// ファイルアップロードボタン
  Widget _buildFileUploadButton() {
    return ElevatedButton(
      onPressed: isProcessing ? null : selectAndProcessFile,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        backgroundColor: isProcessing ? Colors.grey[400] : Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isProcessing) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            const Text('処理中...'),
          ] else ...[
            const Icon(Icons.upload_file),
            const SizedBox(width: 8),
            const Text('音声ファイルを選択'),
          ],
        ],
      ),
    );
  }

  /// ファイル選択状態の表示
  Widget _buildFileStatus() {
    if (selectedFileName != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          border: Border.all(color: Colors.green[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green[600]),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'ファイル: $selectedFileName',
                style: TextStyle(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              'ファイルが選択されていません',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
        ),
      );
    }
  }

  /// 処理中インジケーターまたはグラフの表示
  Widget _buildProcessingOrChart() {
    if (isProcessing) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'ピッチ解析を実行中です...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '音声ファイルのサイズによっては時間がかかる場合があります',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else if (pitchDataList.isNotEmpty) {
      return _buildPitchChart();
    } else {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '音声ファイルを選択してピッチ解析を開始してください',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'MP3ファイル（最大10MB）に対応しています',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }

  /// ピッチカーブのチャート
  Widget _buildPitchChart() {
    return Container(
      height: AppConstants.chartHeight,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          minY: AppConstants.minPitchY,
          maxY: AppConstants.maxPitchY,
          maxX: audioLength,
          lineBarsData: List.generate(pitchDataList.length, (index) {
            return LineChartBarData(
              spots: pitchDataList[index],
              isCurved: true,
              color: Colors.blue,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false), // 点を非表示にしてスムーズに
            );
          }),
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: true,
            horizontalInterval: 1.0,
            verticalInterval: _calculateTimeInterval(audioLength),
            getDrawingHorizontalLine: (value) {
              return const FlLine(
                color: Colors.grey,
                strokeWidth: 0.5,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.3),
                strokeWidth: 0.5,
              );
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (color) => const Color(0xFF42A5F5),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((touchedSpot) {
                  // 対数値から周波数（Hz）に逆変換して表示
                  final double frequencyHz = pow(2, touchedSpot.y).toDouble();
                  final String formattedHz =
                      ((frequencyHz * 100).floor() / 100).toString();
                  return LineTooltipItem(
                    "$formattedHz Hz",
                    const TextStyle(),
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                getTitlesWidget: (value, meta) {
                  return _buildFrequencyLabel(value);
                },
                showTitles: true,
                interval: 1,
                reservedSize: 50.0,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                getTitlesWidget: (value, meta) {
                  return _buildTimeLabel(value);
                },
                showTitles: true,
                interval: _calculateTimeInterval(audioLength),
                reservedSize: 32.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// フッター
  Widget _buildFooter() {
    return const SelectableText(
      '© 2024 laTH　https://lath-memorandum.netlify.app/profiel',
      textAlign: TextAlign.center,
    );
  }

  /// 周波数軸のラベルを作成（音楽的な表記で見やすく）
  Widget _buildFrequencyLabel(double value) {
    // 対数値から周波数に変換
    final double frequency = pow(2, value).toDouble();

    String freqText;
    if (value == 10) {
      // 最上位は "Hz" を付ける
      freqText = '${frequency.round()} Hz';
    } else if (value >= 6 && value <= 9) {
      // 中間は数値のみ
      if (frequency >= 1000) {
        freqText = '${(frequency / 1000).toStringAsFixed(1)}k';
      } else {
        freqText = '${frequency.round()}';
      }
    } else {
      // 範囲外は空文字
      freqText = '';
    }

    return Text(
      freqText,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.grey,
      ),
    );
  }

  /// 時間軸の間隔を計算（音声の長さに応じて調整、重複を防ぐ）
  double _calculateTimeInterval(double audioLength) {
    // 最低でも3-5個のラベルが表示されるように間隔を調整
    if (audioLength <= 2) return audioLength / 8; // 8分割
    if (audioLength <= 5) return audioLength / 10; // 10分割
    if (audioLength <= 10) return 1.0; // 1秒間隔
    if (audioLength <= 30) return audioLength / 15; // 15分割（約2秒間隔）
    if (audioLength <= 60) return audioLength / 12; // 12分割（約5秒間隔）
    if (audioLength <= 180) return audioLength / 18; // 18分割（約10秒間隔）
    return audioLength / 20; // 20分割（長い音声用）
  }

  /// 時間軸のラベルを作成（見やすい形式で表示）
  Widget _buildTimeLabel(double value) {
    // 小数点第2位で四捨五入
    final double roundedValue = (value * 100).round() / 100;

    // 秒数に応じてフォーマットを調整
    String timeText;
    if (roundedValue >= 60) {
      // 1分以上の場合は "分:秒" 形式
      final int minutes = roundedValue ~/ 60;
      final int seconds = (roundedValue % 60).round();
      timeText = '${minutes}:${seconds.toString().padLeft(2, '0')}';
    } else if (roundedValue >= 10) {
      // 10秒以上の場合は整数表示
      timeText = '${roundedValue.round()}s';
    } else {
      // 10秒未満の場合は小数点1桁まで表示
      timeText = '${roundedValue.toStringAsFixed(1)}s';
    }

    return Text(
      timeText,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.grey,
      ),
    );
  }
}
