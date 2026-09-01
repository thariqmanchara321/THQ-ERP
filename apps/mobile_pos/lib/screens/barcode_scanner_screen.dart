import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
class BarcodeScannerScreen extends StatefulWidget {const BarcodeScannerScreen({super.key});@override State<BarcodeScannerScreen> createState()=>_BarcodeScannerScreenState();}
class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>{bool _done=false;@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Scan barcode / serial')),body:MobileScanner(onDetect:(capture){if(_done)return;for(final code in capture.barcodes){final raw=code.rawValue?.trim()??'';if(raw.isNotEmpty){_done=true;Navigator.of(context).pop(raw);break;}}}));}
