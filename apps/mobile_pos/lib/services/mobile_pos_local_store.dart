import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/pos_models.dart';

class MobilePosLocalStore {
  MobilePosLocalStore._();
  static final instance=MobilePosLocalStore._();
  Database? _db;
  Future<Database> get db async {
    if(_db!=null)return _db!;
    final support=await getApplicationSupportDirectory();
    final path=p.join(support.path,'thq_mobile_pos_v488.sqlite');
    _db=await openDatabase(path,version:1,onCreate:(d,_) async {
      await d.execute('CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await d.execute('CREATE TABLE products(tenant_id TEXT NOT NULL,location_id TEXT NOT NULL,variant_id TEXT NOT NULL,payload_json TEXT NOT NULL,available_qty REAL NOT NULL DEFAULT 0,refreshed_at TEXT NOT NULL,PRIMARY KEY(tenant_id,location_id,variant_id))');
      await d.execute('CREATE TABLE customers(tenant_id TEXT NOT NULL,customer_id TEXT NOT NULL,payload_json TEXT NOT NULL,refreshed_at TEXT NOT NULL,PRIMARY KEY(tenant_id,customer_id))');
      await d.execute('CREATE TABLE serials(tenant_id TEXT NOT NULL,location_id TEXT NOT NULL,serial_id TEXT NOT NULL,serial_number TEXT NOT NULL,variant_id TEXT NOT NULL,updated_at TEXT,reserved_request_id TEXT,PRIMARY KEY(tenant_id,serial_id),UNIQUE(tenant_id,serial_number))');
      await d.execute('CREATE TABLE invoices(request_id TEXT PRIMARY KEY,tenant_id TEXT NOT NULL,location_id TEXT NOT NULL,device_id TEXT NOT NULL,local_number TEXT NOT NULL,payload_json TEXT NOT NULL,status TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,conflict_code TEXT,conflict_message TEXT,server_response_json TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)');
      await d.execute('CREATE INDEX idx_mobile_pos_queue ON invoices(tenant_id,device_id,status,created_at)');
      await d.execute('CREATE INDEX idx_mobile_pos_serials ON serials(tenant_id,location_id,variant_id,reserved_request_id)');
    });
    return _db!;
  }

  Future<void> setMeta(String key,Object? value) async {final d=await db;final now=DateTime.now().toUtc().toIso8601String();await d.insert('meta',{'key':key,'value':jsonEncode(value),'updated_at':now},conflictAlgorithm:ConflictAlgorithm.replace);}
  Future<dynamic> getMeta(String key) async {final d=await db;final rows=await d.query('meta',columns:['value'],where:'key=?',whereArgs:[key],limit:1);if(rows.isEmpty)return null;try{return jsonDecode(rows.first['value'] as String);}catch(_){return rows.first['value'];}}

  Future<void> replaceCatalogue({required String tenantId,required String locationId,required List<Map<String,dynamic>> products,required List<Map<String,dynamic>> customers,required List<Map<String,dynamic>> serials,required Map<String,dynamic> manifest}) async {
    final d=await db;final now=DateTime.now().toUtc().toIso8601String();
    await d.transaction((tx) async {
      await tx.delete('products',where:'tenant_id=? AND location_id=?',whereArgs:[tenantId,locationId]);
      for(final row in products){final p=MobileProduct.fromMap(row);await tx.insert('products',{'tenant_id':tenantId,'location_id':locationId,'variant_id':p.variantId,'payload_json':jsonEncode(row),'available_qty':p.stockQuantity,'refreshed_at':now});}
      await tx.delete('customers',where:'tenant_id=?',whereArgs:[tenantId]);
      for(final row in customers){final c=MobileCustomer.fromMap(row);if(c.id.isNotEmpty)await tx.insert('customers',{'tenant_id':tenantId,'customer_id':c.id,'payload_json':jsonEncode(row),'refreshed_at':now});}
      await tx.delete('serials',where:'tenant_id=? AND location_id=?',whereArgs:[tenantId,locationId]);
      for(final row in serials){await tx.insert('serials',{'tenant_id':tenantId,'location_id':locationId,'serial_id':row['serial_id']?.toString()??'','serial_number':row['serial_number']?.toString()??'','variant_id':row['variant_id']?.toString()??'','updated_at':row['updated_at']?.toString(),'reserved_request_id':null});}
      await _reapplyReservations(tx,tenantId,locationId);
    });
    await setMeta('manifest:$tenantId:$locationId',manifest);
  }

  Future<List<MobileProduct>> products(String tenantId,String locationId) async {final d=await db;final rows=await d.query('products',where:'tenant_id=? AND location_id=?',whereArgs:[tenantId,locationId],orderBy:'variant_id');return rows.map((r){final m=Map<String,dynamic>.from(jsonDecode(r['payload_json'] as String) as Map);m['stock_quantity']=((r['available_qty'] as num?)?.toDouble()??0).clamp(0,double.infinity);m['offline_available_quantity']=m['stock_quantity'];return MobileProduct.fromMap(m);}).toList();}
  Future<List<MobileCustomer>> customers(String tenantId) async {final d=await db;final rows=await d.query('customers',where:'tenant_id=?',whereArgs:[tenantId],orderBy:'customer_id');return rows.map((r)=>MobileCustomer.fromMap(Map<String,dynamic>.from(jsonDecode(r['payload_json'] as String) as Map))).toList();}
  Future<Map<String,dynamic>?> findSerial(String tenantId,String locationId,String code) async {final d=await db;final rows=await d.query('serials',where:'tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id IS NULL',whereArgs:[tenantId,locationId,code.trim()],limit:1);return rows.isEmpty?null:Map<String,dynamic>.from(rows.first);}

  Future<String> queueSale({required String requestId,required String tenantId,required String locationId,required String deviceId,required Map<String,dynamic> payload}) async {
    final d=await db;final old=await d.query('invoices',columns:['local_number'],where:'request_id=?',whereArgs:[requestId],limit:1);if(old.isNotEmpty)return old.first['local_number'] as String;
    final n=DateTime.now();final stamp='${n.year.toString().padLeft(4,'0')}${n.month.toString().padLeft(2,'0')}${n.day.toString().padLeft(2,'0')}-${n.hour.toString().padLeft(2,'0')}${n.minute.toString().padLeft(2,'0')}${n.second.toString().padLeft(2,'0')}-${n.millisecond.toString().padLeft(3,'0')}';final local='MOB-$stamp';final full=Map<String,dynamic>.from(payload)..['local_invoice_number']=local..['channel']='mobile_pos';final iso=n.toUtc().toIso8601String();
    await d.transaction((tx) async {await _applyReservation(tx,tenantId,locationId,requestId,full,-1);await tx.insert('invoices',{'request_id':requestId,'tenant_id':tenantId,'location_id':locationId,'device_id':deviceId,'local_number':local,'payload_json':jsonEncode(full),'status':'pending','attempts':0,'created_at':iso,'updated_at':iso});});return local;
  }

  Future<List<LocalInvoice>> queue(String tenantId,String deviceId,{Set<String>? statuses,int limit=300}) async {final d=await db;final where=StringBuffer('tenant_id=? AND device_id=?');final args=<Object?>[tenantId,deviceId];if(statuses!=null&&statuses.isNotEmpty){where.write(' AND status IN (${List.filled(statuses.length,'?').join(',')})');args.addAll(statuses);}final rows=await d.query('invoices',where:where.toString(),whereArgs:args,orderBy:'created_at DESC',limit:limit);return rows.map(_invoice).toList();}
  Future<Map<String,int>> summary(String tenantId,String deviceId) async {final rows=await queue(tenantId,deviceId,limit:10000);final out=<String,int>{};for(final r in rows){out[r.status]=(out[r.status]??0)+1;}return out;}
  Future<void> markSyncing(String id) async=>_status(id,'syncing',attempt:true);
  Future<void> markPending(String id,[String? message]) async=>_status(id,'pending',message:message);
  Future<void> markConflict(String id,String code,String message) async {final d=await db;await d.update('invoices',{'status':'conflict','conflict_code':code,'conflict_message':message,'updated_at':DateTime.now().toUtc().toIso8601String()},where:'request_id=?',whereArgs:[id]);}
  Future<void> markSynced(String id,Map<String,dynamic> response) async {final d=await db;await d.update('invoices',{'status':'synced','conflict_code':null,'conflict_message':null,'server_response_json':jsonEncode(response),'updated_at':DateTime.now().toUtc().toIso8601String()},where:'request_id=?',whereArgs:[id]);}
  Future<void> retry(String id) async=>_status(id,'pending');
  Future<void> cancel(String id) async {final d=await db;final rows=await d.query('invoices',where:'request_id=?',whereArgs:[id],limit:1);if(rows.isEmpty)return;final status=rows.first['status'] as String;if(status=='synced')throw StateError('A synchronized invoice cannot be cancelled locally.');if(status=='cancelled')return;final payload=Map<String,dynamic>.from(jsonDecode(rows.first['payload_json'] as String) as Map);await d.transaction((tx) async {await _applyReservation(tx,rows.first['tenant_id'] as String,rows.first['location_id'] as String,id,payload,1);await tx.update('invoices',{'status':'cancelled','updated_at':DateTime.now().toUtc().toIso8601String()},where:'request_id=?',whereArgs:[id]);});}
  Future<void> _status(String id,String status,{String? message,bool attempt=false}) async {final d=await db;final values=<String,Object?>{'status':status,'conflict_message':message,'updated_at':DateTime.now().toUtc().toIso8601String()};if(attempt){await d.rawUpdate('UPDATE invoices SET status=?,attempts=attempts+1,conflict_message=?,updated_at=? WHERE request_id=?',[status,message,values['updated_at'],id]);}else{await d.update('invoices',values,where:'request_id=?',whereArgs:[id]);}}

  LocalInvoice _invoice(Map<String,Object?> r)=>LocalInvoice(requestId:r['request_id'] as String,localNumber:r['local_number'] as String,status:r['status'] as String,payload:Map<String,dynamic>.from(jsonDecode(r['payload_json'] as String) as Map),attempts:(r['attempts'] as int?)??0,conflictCode:r['conflict_code']?.toString()??'',conflictMessage:r['conflict_message']?.toString()??'',createdAt:DateTime.tryParse(r['created_at']?.toString()??'')??DateTime.now());
  Future<void> _reapplyReservations(DatabaseExecutor tx,String tenant,String location) async {final rows=await tx.query('invoices',columns:['request_id','payload_json'],where:"tenant_id=? AND location_id=? AND status IN ('pending','syncing','conflict','error')",whereArgs:[tenant,location],orderBy:'created_at');for(final r in rows){await _applyReservation(tx,tenant,location,r['request_id'] as String,Map<String,dynamic>.from(jsonDecode(r['payload_json'] as String) as Map),-1,strict:false);}}
  Future<void> _applyReservation(DatabaseExecutor tx,String tenant,String location,String request,Map<String,dynamic> payload,int direction,{bool strict=true}) async {
    for(final raw in (payload['items'] as List? ?? const []).whereType<Map>()){
      final item=Map<String,dynamic>.from(raw);final variant=item['variant_id']?.toString()??'';if(variant.isEmpty)continue;final base=numberValue(item['base_quantity'],numberValue(item['quantity'])*numberValue(item['conversion_to_base'],1));
      if(base>0){final stock=await tx.query('products',columns:['available_qty'],where:'tenant_id=? AND location_id=? AND variant_id=?',whereArgs:[tenant,location,variant],limit:1);if(direction<0&&strict&&stock.isNotEmpty&&numberValue(stock.first['available_qty'])+0.000001<base)throw StateError('Not enough offline stock for ${item['product_name']??item['sku']??'product'}.');await tx.rawUpdate('UPDATE products SET available_qty=available_qty+? WHERE tenant_id=? AND location_id=? AND variant_id=?',[direction*base,tenant,location,variant]);}
      for(final serial in (item['serial_numbers'] as List? ?? const []).map((e)=>e.toString()).where((e)=>e.isNotEmpty)){
        if(direction<0){final changed=await tx.rawUpdate('UPDATE serials SET reserved_request_id=? WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND (reserved_request_id IS NULL OR reserved_request_id=?)',[request,tenant,location,serial,request]);if(strict&&changed==0)throw StateError('Serial $serial is not available offline.');}else{await tx.rawUpdate('UPDATE serials SET reserved_request_id=NULL WHERE tenant_id=? AND location_id=? AND lower(serial_number)=lower(?) AND reserved_request_id=?',[tenant,location,serial,request]);}
      }
    }
  }
}
