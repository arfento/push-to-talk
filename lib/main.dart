import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:push_to_talk_app/firebase_options.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/auth/login_screen.dart';
import 'package:push_to_talk_app/views/auth/register_screen.dart';
import 'package:push_to_talk_app/views/home/walkie_talkie_screen.dart';
import 'package:push_to_talk_app/views/ptt_screen.dart';
import 'package:push_to_talk_app/views/udp/lobby_screen.dart';
import 'package:push_to_talk_app/views/udp/udp_home_screen.dart';
import 'package:push_to_talk_app/views/video_stream/video_home_page.dart';
import 'package:push_to_talk_app/views/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Project ID: ${Firebase.app().options.projectId}');
  } catch (error) {
    print('Firebase initialization error: $error');
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primaryColor: kColourPrimary,
        scaffoldBackgroundColor: kColourBackground,
        cupertinoOverrideTheme: CupertinoThemeData(
          primaryColor: kColourPrimary,
        ),
      ),
      initialRoute: PTTScreen.id,
      routes: {
        PTTScreen.id: (context) => PTTScreen(),
        WelcomeScreen.id: (context) => WelcomeScreen(),
        RegisterScreen.id: (context) => RegisterScreen(),
        LoginScreen.id: (context) => LoginScreen(),
        WalkieTalkieScreen.id: (context) => WalkieTalkieScreen(),
        UdpHomeScreen.id: (context) => UdpHomeScreen(),
        VideoHomePage.id: (context) => VideoHomePage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == LobbyScreen.id) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) {
              return LobbyScreen(
                isHost: args['isHost'] as bool,
                hostIp: args['hostIp'] as String,
              );
            },
          );
        }
        return null;
      },
      // home: UdpHomeScreen(),
      // initialRoute: WelcomeScreen.id,
      // routes: {
      //   WelcomeScreen.id: (context) => WelcomeScreen(),
      //   RegisterScreen.id: (context) => RegisterScreen(),
      //   LoginScreen.id: (context) => LoginScreen(),
      //   WalkieTalkieScreen.id: (context) => WalkieTalkieScreen(),
      // },
      // home: VideoHomePage(),
    );
  }
}
