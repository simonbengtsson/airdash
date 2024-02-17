import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../helpers.dart';
import '../model/device.dart';
import '../reporting/analytics_logger.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';

class PairingDialog extends StatefulWidget {
  final Device localDevice;
  final Function(Device) onPair;

  const PairingDialog(
      {super.key, required this.localDevice, required this.onPair});

  @override
  State<PairingDialog> createState() => PairingDialogState();
}

class PairingDialogState extends State<PairingDialog> {
  final addReceiverIdController = TextEditingController();
  final addReceiverNameController = TextEditingController();
  String localPairingCode = generateCode();
  String remotePairingCode = '';

  String? statusMessage;
  String? errorMessage;

  static String generateCode() {
    var rnd = Random(DateTime.now().millisecondsSinceEpoch);
    var code = rnd.nextInt(10000).toString().padLeft(4, '0');
    return code;
  }

  bool get isPairingEnabled {
    return statusMessage != null || remotePairingCode.length != 4;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.only(left: 24, right: 24, top: 15),
      insetPadding: const EdgeInsets.all(0),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10.0))),
      title: const Text('Pair New Device'),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Enter the pairing code from another device below. Also enter your pairing code on that device.'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pairing Code',
                      style: TextStyle(color: Color.fromRGBO(0, 0, 0, 0.7))),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Container(
                      color: statusMessage == null
                          ? null
                          : const Color.fromRGBO(230, 230, 230, 1),
                      child: SizedBox(
                        width: 90,
                        child: TextField(
                            style: const TextStyle(
                              letterSpacing: 3,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                            enabled: statusMessage == null,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofocus: true,
                            controller: addReceiverIdController,
                            keyboardType: TextInputType.number,
                            onSubmitted: isPairingEnabled
                                ? null
                                : (text) async {
                                    await handlePairing();
                                  },
                            onChanged: (text) {
                              setState(() {
                                errorMessage = null;
                                remotePairingCode = text;
                              });
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: '',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9]')),
                              LengthLimitingTextInputFormatter(4),
                            ]),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your Pairing Code',
                      style: TextStyle(
                          color: Color.fromRGBO(0, 0, 0, 0.7), height: 2)),
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(localPairingCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            fontSize: 20)),
                  ),
                ],
              ),
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Container(
                    padding: const EdgeInsets.only(
                        top: 8, bottom: 8, right: 15, left: 15),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: const Color.fromRGBO(0, 0, 0, 0.1)),
                    child: Text(errorMessage ?? ''),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: TextButton(
            onPressed: isPairingEnabled
                ? null
                : () async {
                    await handlePairing();
                  },
            child: Text(statusMessage ?? 'Start Pairing'),
          ),
        ),
      ],
    );
  }

  Future<void> handlePairing() async {
    AnalyticsEvent.pairingStarted.log();

    setState(() {
      statusMessage = 'Pairing...';
    });

    try {
      var response = await pairRemote(localPairingCode, remotePairingCode);
      String remoteKey = response['deviceKey']! as String;
      var remoteName = response['deviceName'] as String? ?? 'Unknown';
      var platform = response['devicePlatform'] as String?;
      var meta =
          response['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
      var userId = meta['userId'] as String?;
      var device = Device(remoteKey, remoteName, platform, userId);
      await widget.onPair(device);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error, stack) {
      ErrorLogger.logStackError('pairingError', error, stack);
      if (mounted) {
        setState(() {
          errorMessage = 'Pairing failed. Try again.';
          statusMessage = null;
        });
        addReceiverIdController.text = '';
      }
    }
  }

  Future<Map<String, dynamic>> pairRemote(
      String localCode, String remoteCode) async {
    logger('PAIRING: Started pairing with $remoteCode');

    var reqBody = jsonEncode({
      'deviceKey': widget.localDevice.id,
      'localCode': localCode,
      'remoteCode': remoteCode,
      'meta': {
        'deviceName': widget.localDevice.name,
        'devicePlatform': widget.localDevice.platform,
        'userId': widget.localDevice.userId,
      },
    });

    logger('MAIN: Pairing request $reqBody');

    var result = await http.post(
      Uri.parse(Config.getPairingFunctionUrl()),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: reqBody,
    );

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(result.body) as Map<String, dynamic>;
    } catch (_) {}
    if (body == null || result.statusCode != 200) {
      throw LogError('pairingHttpError', null, null, <String, dynamic>{
        'statusCode': result.statusCode,
        'reason': result.reasonPhrase,
        'responseBody': result.body,
        'requestBody': reqBody,
      });
    }

    logger('PAIRING: Pairing response ${result.body}');
    return body;
  }
}
