import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/auth/login_screen.dart';
import 'package:push_to_talk_app/views/auth/register_screen.dart';
import 'package:push_to_talk_app/views/home/walkie_talkie_screen.dart';

class WelcomeScreen extends StatefulWidget {
  static const String id = 'welcome_screen';

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? controller;
  Animation? animationBounce;
  Animation? animationColour;
  bool _checkingAuth = true;

  @override
  void initState() {
    super.initState();
    setupAnimations();
    _checkAuthStatus();
  }

  void _checkAuthStatus() async {
    try {
      // Add a small delay to ensure Firebase Auth state is updated
      await Future.delayed(Duration(milliseconds: 100));

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && mounted) {
        Navigator.pushReplacementNamed(context, WalkieTalkieScreen.id);
      }
    } catch (error) {
      print('Auth check error: $error');
    } finally {
      if (mounted) {
        setState(() => _checkingAuth = false);
      }
    }
  }

  void setupAnimations() {
    controller = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    animationBounce = CurvedAnimation(
      parent: controller!,
      curve: Curves.bounceOut,
    );
    animationColour = ColorTween(
      begin: Colors.black,
      end: kColourBackground,
    ).animate(controller!);
    controller!.forward();
  }

  Widget buildAnimatedWelcomeText() {
    String welcomeText = 'Welcome to Walkie';
    int durationInSeconds = 1;
    int millisecondInterval = (durationInSeconds * 1000 / (welcomeText.length))
        .round();

    return TyperAnimatedTextKit(
      text: [welcomeText],
      textStyle: kTextStyleTitle,
      textAlign: TextAlign.center,
      isRepeatingAnimation: false,
      speed: Duration(milliseconds: millisecondInterval),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: animationColour?.value ?? kColourBackground,
      appBar: AppBar(title: Text(kAppTitle, style: kTextStyleAppTitle)),
      body: SafeArea(
        child: Padding(
          padding: kPaddingSafeArea,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // Logo section with fixed height
              // Expanded(
              //   child: Container(
              //     alignment: Alignment.center,
              //     child: Hero(
              //       tag: 'logo',
              //       child: Container(
              //         child: Image.asset('assets/images/walkie.png'),
              //       ),
              //     ),
              //   ),
              // ),

              // Buttons section
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(height: 30),
                  // buildAnimatedWelcomeText(),
                  SizedBox(height: 20),
                  ElevatedButton(
                    child: Text('Sign In', style: kTextStyleFormButton),
                    style: ElevatedButton.styleFrom(
                      padding: kPaddingFormButton,
                      backgroundColor: kColourPrimary,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, LoginScreen.id);
                    },
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    child: Text('Register', style: kTextStyleFormButton),
                    style: ElevatedButton.styleFrom(
                      padding: kPaddingFormButton,
                      backgroundColor: kColourPrimary,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, RegisterScreen.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
