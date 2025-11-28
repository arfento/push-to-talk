import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:push_to_talk_app/firebase_options.dart';
import 'package:push_to_talk_app/core/constants/constants.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/screens/radio_streaming/pcm_streaming_screen.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/screens/radio_streaming/radio_streaming_screen.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/screens/record_screen/audio_record_screen.dart';
import 'package:push_to_talk_app/presentation/cubit/record_cubit.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/screens/recordings_list/cubit/files_cubit.dart';
import 'package:push_to_talk_app/presentation/pages/audio_record/screens/recordings_list/recordings_list_screen.dart';
import 'package:push_to_talk_app/presentation/pages/auth/login_screen.dart';
import 'package:push_to_talk_app/presentation/pages/auth/register_screen.dart';
import 'package:push_to_talk_app/presentation/pages/home/walkie_talkie_screen.dart';
import 'package:push_to_talk_app/presentation/ptt_screen.dart';
import 'package:push_to_talk_app/presentation/pages/lobby/lobby_screen.dart';
import 'package:push_to_talk_app/presentation/pages/lobby/create_lobby_screen.dart';
import 'package:push_to_talk_app/presentation/welcome_screen.dart';

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
    return MultiBlocProvider(
      providers: [
        BlocProvider<RecordCubit>(create: (context) => RecordCubit()),

        /// [FilesCubit] is provided before material app because it should start loading all files when app is opens
        /// asynschronous method [getFiles] is called in constructor of [Files Cubit].
        BlocProvider<FilesCubit>(create: (context) => FilesCubit()),
      ],
      child: MaterialApp(
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
          CreateLobbyScreen.id: (context) => CreateLobbyScreen(),
          AudioRecordScreen.routeName: (context) => AudioRecordScreen(),
          RecordingsListScreen.routeName: (context) => RecordingsListScreen(),
          RadioStreamingScreen.routeName: (context) => RadioStreamingScreen(),
          PCMStreamingScreen.routeName: (context) => PCMStreamingScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == LobbyScreen.id) {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) {
                return LobbyScreen(
                  isHost: args['isHost'] as bool,
                  hostIp: args['hostIp'] as String,
                  lobbyId: args['lobbyId'] as String,
                );
              },
            );
          }
          return null;
        },
        // home: CreateLobbyScreen(),
        // initialRoute: WelcomeScreen.id,
        // routes: {
        //   WelcomeScreen.id: (context) => WelcomeScreen(),
        //   RegisterScreen.id: (context) => RegisterScreen(),
        //   LoginScreen.id: (context) => LoginScreen(),
        //   WalkieTalkieScreen.id: (context) => WalkieTalkieScreen(),
        // },
        // home: VideoHomePage(),
      ),
    );
  }
}
