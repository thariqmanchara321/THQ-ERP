import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_auth_service.dart';
import '../services/mobile_session_service.dart';
import 'mobile_home_screen.dart';

class MobileEntryScreen extends StatefulWidget { const MobileEntryScreen({super.key}); @override State<MobileEntryScreen> createState()=>_MobileEntryScreenState(); }
class _MobileEntryScreenState extends State<MobileEntryScreen> {
  late Future<DeviceActivation?> _activation;
  @override void initState(){super.initState();_activation=DeviceInstallationService().readActivation();}
  @override Widget build(BuildContext context)=>FutureBuilder<DeviceActivation?>(future:_activation,builder:(context,snapshot){
    if(snapshot.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if (snapshot.data == null) {
    return _ActivationView(
    onDone: () {
      setState(() {
        _activation = DeviceInstallationService().readActivation();
      });
    },
    );
    }
    if(Supabase.instance.client.auth.currentSession==null)return _LoginView(onDone:(){setState((){});});
    return const _SessionLoader();
  });
}
class _ActivationView extends StatefulWidget { final VoidCallback onDone; const _ActivationView({required this.onDone}); @override State<_ActivationView> createState()=>_ActivationViewState(); }
class _ActivationViewState extends State<_ActivationView>{ final _business=TextEditingController();final _code=TextEditingController();bool _busy=false;String? _error;
  @override void dispose(){_business.dispose();_code.dispose();super.dispose();}
  Future<void> _activate()async{if(_busy)return;setState(()=>_busy=true);try{await DeviceInstallationService().activate(businessCode:_business.text,activationCode:_code.text);widget.onDone();}catch(e){if(mounted)setState(()=>_error=e.toString());}finally{if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[const SizedBox(height:40),const Icon(Icons.phone_android,size:64),const SizedBox(height:18),Text('THQ Client Mobile',style:Theme.of(context).textTheme.headlineMedium,textAlign:TextAlign.center),const SizedBox(height:8),const Text('Activate this phone using a Client system activation code from THQ Admin.',textAlign:TextAlign.center),const SizedBox(height:28),TextField(controller:_business,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Business code',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:_code,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Activation code',border:OutlineInputBorder())),if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),const SizedBox(height:16),FilledButton.icon(onPressed:_busy?null:_activate,icon:const Icon(Icons.verified_user_outlined),label:Text(_busy?'Activating...':'Activate Client Mobile'))])));
}
class _LoginView extends StatefulWidget { final VoidCallback onDone; const _LoginView({required this.onDone}); @override State<_LoginView> createState()=>_LoginViewState(); }
class _LoginViewState extends State<_LoginView>{final _username=TextEditingController();final _password=TextEditingController();bool _busy=false;String? _error;
  @override void dispose(){_username.dispose();_password.dispose();super.dispose();}
  Future<void> _login()async{if(_busy)return;setState(()=>_busy=true);try{await MobileAuthService().signIn(username:_username.text,password:_password.text);widget.onDone();}catch(e){if(mounted)setState(()=>_error=e.toString());}finally{if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[const SizedBox(height:48),const Icon(Icons.business_center_outlined,size:64),const SizedBox(height:18),Text('Sign in',style:Theme.of(context).textTheme.headlineMedium,textAlign:TextAlign.center),const SizedBox(height:24),TextField(controller:_username,autocorrect:false,decoration:const InputDecoration(labelText:'Username',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:_password,obscureText:true,onSubmitted:(_)=>_login(),decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),const SizedBox(height:16),FilledButton(onPressed:_busy?null:_login,child:Text(_busy?'Signing in...':'Sign in'))])));
}
class _SessionLoader extends StatelessWidget { const _SessionLoader(); @override Widget build(BuildContext context)=>FutureBuilder(future:MobileSessionService().load(),builder:(context,snapshot){if(snapshot.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));if(snapshot.hasError)return Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(snapshot.error.toString()))));return MobileHomeScreen(session:snapshot.data!);}); }
