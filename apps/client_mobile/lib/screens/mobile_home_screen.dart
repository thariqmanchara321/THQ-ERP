import 'package:flutter/material.dart';
import '../models/mobile_session.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_auth_service.dart';
import '../services/mobile_client_service.dart';
import 'mobile_entry_screen.dart';

class MobileHomeScreen extends StatefulWidget { final MobileSession session; const MobileHomeScreen({super.key,required this.session}); @override State<MobileHomeScreen> createState()=>_MobileHomeScreenState(); }
class _MobileHomeScreenState extends State<MobileHomeScreen>{ final _service=MobileClientService();int _index=0;String? _locationId;late Future<Map<String,dynamic>> _dashboard;
  @override void initState(){super.initState();_locationId=widget.session.canViewAllLocations?null:widget.session.locationId;_dashboard=_service.dashboard(widget.session,locationId:_locationId);}
  void _refresh(){setState(()=>_dashboard=_service.dashboard(widget.session,locationId:_locationId));}
  String money(dynamic v){final n=v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;return '${widget.session.currencyCode} ${n.toStringAsFixed(2)}';}
  @override Widget build(BuildContext context){final pages=[_DashboardTab(session:widget.session,future:_dashboard,money:money,onRefresh:_refresh,locationId:_locationId,onLocation:(v){setState(()=>_locationId=v);_refresh();}),_BusinessTab(open:_open),_ApprovalsTab(session:widget.session,service:_service,money:money),_MoreTab(session:widget.session,service:_service,money:money,onOpen:_open,onLogout:_logout)];return Scaffold(appBar:AppBar(title:Text(widget.session.businessName),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),body:pages[_index],bottomNavigationBar:NavigationBar(selectedIndex:_index,onDestinationSelected:(v)=>setState(()=>_index=v),destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:'Dashboard'),NavigationDestination(icon:Icon(Icons.business_outlined),selectedIcon:Icon(Icons.business),label:'Business'),NavigationDestination(icon:Icon(Icons.approval_outlined),selectedIcon:Icon(Icons.approval),label:'Approvals'),NavigationDestination(icon:Icon(Icons.more_horiz),label:'More') ]));}
  Future<void> _logout()async{await MobileAuthService().signOut();if(!mounted)return;Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const MobileEntryScreen()),(_)=>false);}
  void _open(String key){switch(key){case'sales':_push('Sales Status',()=>_service.sales(widget.session,locationId:_locationId),['sale_number','customer_name','status','grand_total','balance_due']);break;case'purchases':_push('Purchases',()=>_service.purchases(widget.session,locationId:_locationId),['document_type','document_number','supplier_name','status','grand_total','balance_due']);break;case'inventory':_push('Inventory',()=>_service.inventory(widget.session,locationId:_locationId),['product_name','sku','location_name','available','status','stock_value']);break;case'customers':_push('Customer Outstanding',()=>_service.customerOutstanding(widget.session,locationId:_locationId),['customer_name','phone','total_outstanding','days_90_plus','status']);break;case'suppliers':_push('Supplier Outstanding',()=>_service.supplierOutstanding(widget.session,locationId:_locationId),['supplier_name','phone','total_outstanding','days_90_plus','status']);break;case'stores':_push('Store Performance',()=>_service.storePerformance(widget.session),['location_name','net_sales','gross_profit','invoice_count','inventory_value','receivables','payables']);break;}}
  void _push(String title,Future<List<Map<String,dynamic>>> Function() loader,List<String> fields){Navigator.push(context,MaterialPageRoute(builder:(_)=>_DataListPage(title:title,loader:loader,fields:fields,currency:widget.session.currencyCode)));}
}

class _DashboardTab extends StatelessWidget{final MobileSession session;final Future<Map<String,dynamic>> future;final String Function(dynamic) money;final VoidCallback onRefresh;final String? locationId;final ValueChanged<String?> onLocation;const _DashboardTab({required this.session,required this.future,required this.money,required this.onRefresh,required this.locationId,required this.onLocation});
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:()async=>onRefresh(),child:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return ListView(children: const [SizedBox(height:250),Center(child:CircularProgressIndicator())]);if(s.hasError)return ListView(padding:const EdgeInsets.all(20),children:[Text(s.error.toString())]);final d=s.data??{};final a=d['attention'] is Map?Map<String,dynamic>.from(d['attention'] as Map):<String,dynamic>{};return ListView(padding:const EdgeInsets.all(16),children:[if(session.canViewAllLocations)DropdownButtonFormField<String?>(initialValue:locationId,decoration:const InputDecoration(labelText:'Store scope',border:OutlineInputBorder()),items:[const DropdownMenuItem<String?>(value:null,child:Text('All accessible stores')),...session.locations.map((l)=>DropdownMenuItem<String?>(value:l.id,child:Text(l.name)))],onChanged:onLocation),const SizedBox(height:16),Text('Today',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:10),Wrap(spacing:10,runSpacing:10,children:[_Kpi(label:'Net Sales',value:money(d['net_sales']),icon:Icons.point_of_sale),_Kpi(label:'Gross Profit',value:money(d['gross_profit']),icon:Icons.trending_up),_Kpi(label:'Invoices',value:'${d['invoice_count']??0}',icon:Icons.receipt_long),_Kpi(label:'Customer Due',value:money(d['customer_outstanding']),icon:Icons.account_balance_wallet_outlined),_Kpi(label:'Supplier Due',value:money(d['supplier_outstanding']),icon:Icons.payments_outlined),_Kpi(label:'Approvals',value:'${d['pending_approvals']??0}',icon:Icons.approval_outlined)]),const SizedBox(height:20),Text('Attention',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),Card(child:Column(children:[ListTile(leading:const Icon(Icons.warning_amber),title:const Text('Low stock'),trailing:Text('${a['low_stock']??0}')),ListTile(leading:const Icon(Icons.remove_shopping_cart_outlined),title:const Text('Out of stock'),trailing:Text('${a['out_of_stock']??0}')),ListTile(leading:const Icon(Icons.schedule),title:const Text('Overdue receivables'),trailing:Text(money(a['overdue_receivables'])))]))]);}));
}
class _Kpi extends StatelessWidget{final String label,value;final IconData icon;const _Kpi({required this.label,required this.value,required this.icon});@override Widget build(BuildContext context)=>SizedBox(width:(MediaQuery.sizeOf(context).width-42)/2,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon),const SizedBox(height:10),Text(value,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),Text(label,style:Theme.of(context).textTheme.bodySmall)]))));}
class _BusinessTab extends StatelessWidget{final ValueChanged<String> open;const _BusinessTab({required this.open});@override Widget build(BuildContext context){final rows=[('sales','Sales Status',Icons.point_of_sale),('purchases','Purchases',Icons.shopping_cart_outlined),('inventory','Inventory',Icons.inventory_2_outlined),('customers','Customer Outstanding',Icons.people_outline),('suppliers','Supplier Outstanding',Icons.local_shipping_outlined)];return ListView(padding:const EdgeInsets.all(16),children:[Text('Business',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:8),...rows.map((r)=>Card(child:ListTile(leading:Icon(r.$3),title:Text(r.$2),trailing:const Icon(Icons.chevron_right),onTap:()=>open(r.$1))))]);}}
class _ApprovalsTab extends StatefulWidget{final MobileSession session;final MobileClientService service;final String Function(dynamic) money;const _ApprovalsTab({required this.session,required this.service,required this.money});@override State<_ApprovalsTab> createState()=>_ApprovalsTabState();}
class _ApprovalsTabState extends State<_ApprovalsTab>{late Future<List<Map<String,dynamic>>> _future;@override void initState(){super.initState();_future=widget.service.approvals(widget.session);}void _reload()=>setState(()=>_future=widget.service.approvals(widget.session));Future<void> _decide(Map<String,dynamic> row,bool approve)async{final note=await showDialog<String>(context:context,builder:(context)=>_NoteDialog(title:approve?'Approve':'Reject',required:!approve));if(note==null)return;await widget.service.decide(widget.session,type:row['approval_type']?.toString()??'',id:row['id']?.toString()??'',approve:approve,note:note);if(mounted)_reload();}
  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(future:_future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(16),child:Text(s.error.toString())));final rows=s.data??[];if(rows.isEmpty)return const Center(child:Text('No pending approvals'));return RefreshIndicator(onRefresh:()async=>_reload(),child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:rows.length,itemBuilder:(context,i){final r=rows[i];return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r['reference']?.toString()??'',style:const TextStyle(fontWeight:FontWeight.bold)),Text(r['summary']?.toString()??''),if(r['location_name']!=null)Text(r['location_name'].toString()),if(r['amount']!=null)Text(widget.money(r['amount'])),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_decide(r,false),child:const Text('Reject'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>_decide(r,true),child:const Text('Approve')))])])));}),);});}
class _NoteDialog extends StatefulWidget{final String title;final bool required;const _NoteDialog({required this.title,required this.required});@override State<_NoteDialog> createState()=>_NoteDialogState();}class _NoteDialogState extends State<_NoteDialog>{final c=TextEditingController();@override void dispose(){c.dispose();super.dispose();}@override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),content:TextField(controller:c,maxLines:3,decoration:InputDecoration(labelText:widget.required?'Reason required':'Note')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,(!widget.required||c.text.trim().isNotEmpty)?c.text.trim():null),child:Text(widget.title))]);}
class _MoreTab extends StatelessWidget{final MobileSession session;final MobileClientService service;final String Function(dynamic) money;final ValueChanged<String> onOpen;final Future<void> Function() onLogout;const _MoreTab({required this.session,required this.service,required this.money,required this.onOpen,required this.onLogout});@override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[Card(child:ListTile(leading:const Icon(Icons.storefront),title:const Text('Store Performance'),trailing:const Icon(Icons.chevron_right),onTap:()=>onOpen('stores'))),Card(child:ListTile(leading:const Icon(Icons.analytics_outlined),title:const Text('Reports'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_ReportsPage(session:session,service:service,money:money))))),Card(child:ListTile(leading:const Icon(Icons.payments_outlined),title:const Text('Customer Payment'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_CustomerPaymentPage(session:session,service:service,money:money))))),const SizedBox(height:12),Card(child:ListTile(leading:const Icon(Icons.phone_android),title:Text(session.deviceName),subtitle:Text('${session.deviceCode} • ${session.locationName}'))),Card(child:ListTile(leading:const Icon(Icons.logout),title:const Text('Sign out'),onTap:()=>onLogout())),Card(child:ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Deactivate this phone'),onTap:()async{await MobileAuthService().signOut();await DeviceInstallationService().clearActivation();if(context.mounted)Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const MobileEntryScreen()),(_)=>false);} ))]);}

class _DataListPage extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final List<String> fields;
  final String currency;

  const _DataListPage({
    required this.title,
    required this.loader,
    required this.fields,
    required this.currency,
  });

  @override
  State<_DataListPage> createState() => _DataListPageState();
}

class _DataListPageState extends State<_DataListPage> {
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = widget.loader();
  }

  String label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async {
              final next = widget.loader();
              setState(() => future = next);
              await next;
            },
            child: rows.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No data')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: widget.fields
                                .where((key) => row[key] != null)
                                .map(
                                  (key) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            label(key),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            row[key].toString(),
                                            style: TextStyle(
                                              fontWeight: key.contains('name') ||
                                                      key.contains('number')
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
class _ReportsPage extends StatefulWidget{final MobileSession session;final MobileClientService service;final String Function(dynamic) money;const _ReportsPage({required this.session,required this.service,required this.money});@override State<_ReportsPage> createState()=>_ReportsPageState();}
class _ReportsPageState extends State<_ReportsPage>{late DateTime from;late Future<Map<String,dynamic>> f;@override void initState(){super.initState();final now=DateTime.now();from=DateTime(now.year,now.month,1);f=widget.service.report(widget.session,from:from,to:now);} @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Reports')),body:FutureBuilder<Map<String,dynamic>>(future:f,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text(s.error.toString()));final d=s.data??{};return ListView(padding:const EdgeInsets.all(16),children:[Text('Month to date',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:10),...d.entries.map((e)=>Card(child:ListTile(title:Text(e.key.replaceAll('_',' ')),trailing:Text(e.value.toString()))))]);}));}
class _CustomerPaymentPage extends StatefulWidget{final MobileSession session;final MobileClientService service;final String Function(dynamic) money;const _CustomerPaymentPage({required this.session,required this.service,required this.money});@override State<_CustomerPaymentPage> createState()=>_CustomerPaymentPageState();}
class _CustomerPaymentPageState extends State<_CustomerPaymentPage>{late Future<List<Map<String,dynamic>>> f;String? customerId;final amount=TextEditingController();final reference=TextEditingController();String method='cash';bool busy=false;@override void initState(){super.initState();f=widget.service.customerOutstanding(widget.session);}@override void dispose(){amount.dispose();reference.dispose();super.dispose();}Future<void> submit()async{final v=double.tryParse(amount.text.trim())??0;if(customerId==null||v<=0)return;setState(()=>busy=true);try{await widget.service.receiveCustomerPayment(widget.session,customerId:customerId!,amount:v,method:method,reference:reference.text);if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Customer payment recorded.')));Navigator.pop(context);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Customer Payment')),body:FutureBuilder<List<Map<String,dynamic>>>(future:f,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());final rows=s.data??[];return ListView(padding:const EdgeInsets.all(16),children:[DropdownButtonFormField<String>(initialValue:customerId,decoration:const InputDecoration(labelText:'Customer',border:OutlineInputBorder()),items:rows.map((r)=>DropdownMenuItem(value:r['customer_id']?.toString() ?? '',child:Text('${r['customer_name']} • ${widget.money(r['total_outstanding'])}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>customerId=v)),const SizedBox(height:12),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount',border:OutlineInputBorder())),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:method,decoration:const InputDecoration(labelText:'Method',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'cash',child:Text('Cash')),DropdownMenuItem(value:'card',child:Text('Card')),DropdownMenuItem(value:'bank',child:Text('Bank'))],onChanged:(v){if(v!=null)setState(()=>method=v);}),const SizedBox(height:12),TextField(controller:reference,decoration:const InputDecoration(labelText:'Reference',border:OutlineInputBorder())),const SizedBox(height:16),FilledButton(onPressed:busy?null:submit,child:Text(busy?'Saving...':'Receive Payment'))]);}));}
