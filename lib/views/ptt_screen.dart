import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/udp/udp_home_screen.dart';
import 'package:push_to_talk_app/views/welcome_screen.dart';

class PTTScreen extends StatefulWidget {
  static const String id = 'ptt_screen';

  @override
  _PTTScreenState createState() => _PTTScreenState();
}

class _PTTScreenState extends State<PTTScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? controller;
  Animation? animationBounce;
  Animation? animationColour;

  @override
  void initState() {
    super.initState();
    setupAnimations();
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
      backgroundColor: kColourBackground,
      appBar: AppBar(title: Text(kAppTitle, style: kTextStyleAppTitle)),
      body: SafeArea(
        child: Padding(
          padding: kPaddingSafeArea,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Logo section with fixed height
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  child: Hero(
                    tag: 'logo',
                    child: Container(
                      child: Image.asset('assets/images/walkie.png'),
                    ),
                  ),
                ),
              ),

              // Buttons section
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(height: 30),
                  // buildAnimatedWelcomeText(),
                  SizedBox(height: 20),
                  ElevatedButton(
                    child: Text('PTT Firebase', style: kTextStyleFormButton),
                    style: ElevatedButton.styleFrom(
                      padding: kPaddingFormButton,
                      backgroundColor: kColourPrimary,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, WelcomeScreen.id);
                    },
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    child: Text(
                      'PTT Local Network',
                      style: kTextStyleFormButton,
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: kPaddingFormButton,
                      backgroundColor: kColourPrimary,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, UdpHomeScreen.id);
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
