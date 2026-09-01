import 'package:flutter_test/flutter_test.dart';
import 'package:client_mobile/models/mobile_session.dart';
void main(){test('mobile location parses',(){final x=MobileLocation.fromMap({'id':'1','code':'MAIN','name':'Main'});expect(x.name,'Main');});}
