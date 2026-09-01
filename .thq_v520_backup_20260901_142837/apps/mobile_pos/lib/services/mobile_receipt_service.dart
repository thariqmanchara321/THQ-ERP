import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/pos_session.dart';
import '../models/pos_models.dart';
class MobileReceiptService {
  Future<Uint8List> build({required PosSession session,required String localNumber,required Map<String,dynamic> payload,required bool synced}) async {
    final doc=pw.Document();final items=(payload['items'] as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    doc.addPage(pw.Page(pageFormat:PdfPageFormat(80*PdfPageFormat.mm,200*PdfPageFormat.mm,marginAll:4*PdfPageFormat.mm),build:(_)=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Center(child:pw.Text(session.businessName,style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:14))),pw.Center(child:pw.Text(synced?'MOBILE POS RECEIPT':'OFFLINE SALE RECEIPT',style:pw.TextStyle(fontWeight:pw.FontWeight.bold))),if(!synced)pw.Center(child:pw.Text('PENDING SERVER SYNC',style:pw.TextStyle(fontWeight:pw.FontWeight.bold))),pw.Divider(),
      pw.Text('Local No: $localNumber'),pw.Text('Store: ${session.locationCode} • POS: ${session.deviceCode}'),pw.Text('Customer: ${payload['customer_name']??''}'),pw.Text('Date: ${payload['sale_time']??payload['sale_date']??''}'),pw.Divider(),
      ...items.map((i){final q=numberValue(i['quantity']),price=numberValue(i['unit_price']),tax=numberValue(i['tax_rate']),line=q*price*(1+tax/100);return pw.Padding(padding:const pw.EdgeInsets.only(bottom:4),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(i['product_name']?.toString()??i['sku']?.toString()??'Item',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('${_q(q)} ${i['unit_code']??''} × ${_money(session,price)}'),pw.Text(_money(session,line))]),if((i['serial_numbers'] as List?)?.isNotEmpty==true)pw.Text('Serial: ${(i['serial_numbers'] as List).join(', ')}',style:const pw.TextStyle(fontSize:8))]));}),pw.Divider(),
      _row(session,'TOTAL',numberValue(payload['total']),true),_row(session,'PAID',numberValue(payload['initial_payment']),false),if(numberValue(payload['outstanding'])>0.005)_row(session,'DUE',numberValue(payload['outstanding']),false),pw.SizedBox(height:8),if(!synced)pw.Text('Local offline receipt. Final server invoice is assigned after successful synchronization.',style:const pw.TextStyle(fontSize:8)),
    ])));return doc.save();
  }
  Future<void> printReceipt({required PosSession session,required String localNumber,required Map<String,dynamic> payload,required bool synced}) async {final bytes=await build(session:session,localNumber:localNumber,payload:payload,synced:synced);await Printing.layoutPdf(onLayout:(_)=>bytes,name:'THQ $localNumber');}
  Future<void> shareReceipt({required PosSession session,required String localNumber,required Map<String,dynamic> payload,required bool synced}) async {final bytes=await build(session:session,localNumber:localNumber,payload:payload,synced:synced);await Printing.sharePdf(bytes:bytes,filename:'$localNumber.pdf');}
  pw.Widget _row(PosSession s,String label,double v,bool bold)=>pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text(label,style:bold?pw.TextStyle(fontWeight:pw.FontWeight.bold):null),pw.Text(_money(s,v),style:bold?pw.TextStyle(fontWeight:pw.FontWeight.bold):null)]);
  String _q(double v)=>v==v.roundToDouble()?v.toStringAsFixed(0):v.toStringAsFixed(3);String _money(PosSession s,double v)=>'${s.currencyCode} ${v.toStringAsFixed(2)}';
}
