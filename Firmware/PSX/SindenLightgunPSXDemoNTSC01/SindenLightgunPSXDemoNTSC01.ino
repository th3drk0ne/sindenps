//This Arduino code sample is shared under 
//Creative Commons Attribution-NonCommercial 3.0 Unported license
//This applies to only this piece of code and does give any additional permissions or rights
//to any other files that this is bundled with

//This code is a deritive of the version published here by Charlie Cole on his LightgunVerter project:
//https://github.com/charcole/LCDZapper/tree/master/Firmware/ActiveCables
//A big thanks to Charlie for creating and sharing this very useful program

//This version is setup for PAL but changing for NTSC should just be changing a couple of numbers
//and will be figured out when tested.  I think it should work on NTSC as it is but might be less accurate than PAL.

//This code is designed for use on an Arduino Uno R3 but should work on other Arduino boards or clones
//You need an SS pin (Slave Select) which is not always present for example on the pro micro
//The wires to connect are described as you look at psx control port left to right 1-9.

//You can test that your Arduino is interfacing with the PSX correctly by connecting switches to Pins 3,4 and 5 
//against ground which allow you to test a trigger or the buttons, this helps debug any issues
//You can also use this to wire in a pedal to the Arduino
//If you have weird random firing, you might want to disable this

//Baud is set to 57600

//9    DATA - green
//8    COMMAND - blue 
// 7   N/C (9 Volts unused)
// 6   GND - yellow
// 5   VCC
// 4   ATT - orange
// 3   CLOCK - red
// 2   N/C
// 1    ACK - grey

//so
// 1-3 4-6 -89

//ground 6
#define IN_CMD MOSI //8 D11
#define OUT_DATA MISO //9 D12 
#define OUT_ACK 7 //1 D7
#define IN_ATT SS //4 D10
#define IN_CLK SCK //3 D13
//#define OUT_LED 2
#define TestButtonTrigger 5
#define TestButtonA 4
#define TestButtonB 3

#define CONTROLLER_DATA_SIZE 8  // From LightGunVerter

#include <SPI.h>

#define DATA_SIZE 8             // From PSX
uint8_t ReadMask[DATA_SIZE]   = { 0xFF, 0xFF, 0, 0, 0, 0, 0, 0 };
uint8_t ReadExpect[DATA_SIZE] = { 0x01, 0x42, 0, 0, 0, 0, 0, 0 };
uint8_t Reply[DATA_SIZE] = { 0x63, 0x5A, 0xFF, 0xFF, 0x01, 0x00, 0x05, 0x00 };
//uint8_t Reply[DATA_SIZE] = { 0x63, 0x5A, 0xFF, 0xFF, 0xFF, 0x00, 0xA3, 0x00 };

//20-127 pal 32-295
//19-f8 ntsc 25-248


uint8_t ControllerReadIndex = 0;
uint8_t ControllerData[CONTROLLER_DATA_SIZE];
uint8_t DataIndex = 0;
bool bDataGood = true;
bool Trigger = false;
bool AButton = false;

#define ReadAttention() (PINB&(1<<2))
#define WriteAckLow() (DDRD|=(1<<7))
#define WriteAckHigh() (DDRD&=~(1<<7))
#define WriteLEDLow() (PORTD&=~(1<<2))
#define WriteLEDHigh() (PORTD|=(1<<2))
#define DelayMicro() asm("NOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\n")
int testButtonStateTrigger = 0;
int testButtonStateA = 0;
int testButtonStateB = 0;
int LastSerialMouse = 0;
inline int ReadCommand()
{
  return digitalRead(IN_CMD);
}

void setup()
{
  // LED for debugging
  //pinMode(OUT_LED, OUTPUT);
  //digitalWrite(OUT_LED, LOW);

  // Ack (open collector)
  pinMode(OUT_ACK, INPUT);
  digitalWrite(OUT_ACK, 0);

  // Set up SPI
  pinMode(MISO, OUTPUT);
  SPCR |= bit (SPE)|bit(DORD)|bit(CPOL)|bit(CPHA);
  SPI.attachInterrupt();

  //for input
  pinMode(TestButtonTrigger, INPUT_PULLUP);
  pinMode(TestButtonA, INPUT_PULLUP);
  pinMode(TestButtonB, INPUT_PULLUP);


  // Set up LightGunVerter serial
  Serial.begin(57600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }
}

ISR (SPI_STC_vect)
{
  uint8_t DataIn = SPDR;

  if (DataIndex < DATA_SIZE)  // Acknowledge
  {
    bDataGood &= ((DataIn & ReadMask[DataIndex]) == ReadExpect[DataIndex]);
    if (bDataGood)
    {
      SPDR = Reply[DataIndex];
    
      WriteAckLow();
      DelayMicro();
      DelayMicro();
      DelayMicro();
      DelayMicro();
      WriteAckHigh();

      
    }
    else
    {
      SPDR = 0xFF;
      
    }
    DataIndex++;
  }
  else
  {
    SPDR = 0xFF;
  }
}

void loop()
{
// firmware_mode query
if (Serial.available() > 0)
{
    int incoming = Serial.peek();  // look without consuming

    // If it's not your binary packet start byte, treat as command
    if (incoming != 222)
    {
        incoming = Serial.read();

        if (incoming == 'I')   // e.g. send 'I' for identify
        {
            Serial.println("NAMCO-NTSC");
        }
        return; // don't process as gun data
    }
}

if (ReadAttention() != 0)
  {
    if (DataIndex != 0)
    {
      DataIndex = 0;
      bDataGood = true;
    }
      testButtonStateTrigger = digitalRead(TestButtonTrigger);
      testButtonStateA = digitalRead(TestButtonA);
      testButtonStateB = digitalRead(TestButtonB);

      if (Serial.available() > 5) 
      {
                // read the incoming byte:
                int StartByte = Serial.read();
                int SerialX = Serial.read();
                int SerialY = Serial.read();
                int SerialButtonsValue1 = Serial.read();
                int SerialButtonsValue2 = Serial.read();
                int EndByte = Serial.read();

                //Check if format of bytes looks wrong
                if (StartByte != 222 || EndByte != 223)
                {
                      int LookingForEnd = 0;
                      while(LookingForEnd != 223)
                      {
                        //Loop until hit the end byte
                        if (Serial.available() > 0)
                        {
                          LookingForEnd = Serial.read();
                        }
                      }
                }
                else
                {
                    //Data looks good
                  
                //This is used to help with debugging
                Serial.write(SerialButtonsValue1);

                  //Update position converting byte 0-255 to guncon coordinate
                  //if on left or right, top or bottom 3 pixels of screen do offscreen for reload

                  if (SerialX < 3 || SerialX > 252 || SerialY < 3 || SerialY > 252)
                  {
                      //set as off screen
                      Reply[4] = 0x01;
                      Reply[5] = 0x00;
                      Reply[6] = 0x05;
                      Reply[7] = 0x00;
                    
                  }
                  else
                  {

                      //Set for PAL, needs tweaking for NTSC
                      //Coordinates are sent in as 0-255 and mapped
                      //PAL X 77-440? Y 32-295
                      //NTSC X 77-461? Y 25-248



                      float floatx = (float)SerialX;
                      float floaty = (float)SerialY;  

                      float percentx = floatx/255;
                      float percenty = floaty/255;

                      //NTSC untested
                      float positionx = percentx * (440-77) + 77;
                      float positiony = percenty * (294-48) + 48;

                      //PAL
                      //float positionx = percentx * (461-77) + 77;
                      //float positiony = percenty * (295-32) + 32;


                      int posx = (int)positionx;
                      int posy = (int)positiony;

                      if (posx > 255)
                      {
                        Reply[4] = posx-255;
                        Reply[5] = 0x01;  
                      }
                      else
                      {
                        Reply[4] = posx;
                        Reply[5] = 0x00;
                      }

                      if (posy > 255)
                      {
                        Reply[6] = posy-255;
                        Reply[7] = 0x01;  
                      }
                      else
                      {
                        Reply[6] = posy;
                        Reply[7] = 0x00;
                      }
                  }
                
                  //set buttons
                  Reply[2] = 0xFF;
                  Reply[3] = 0xFF;

                  //Break down of SerialButtonsValues
                  //SerialButtonValues1 1 Trigger
                  //SerialButtonValues1 2 Pump Action
                  //SerialButtonValues1 4 FrontLeft
                  //SerialButtonValues1 8 FrontRight
                  //SerialButtonValues1 16 BackLeft
                  //SerialButtonValues1 32 BackRight
                  //SerialButtonValues2 1 Up
                  //SerialButtonValues2 2 Down
                  //SerialButtonValues2 4 Left
                  //SerialButtonValues2 8 Right

                  if ((SerialButtonsValue1 & 8) != 0 || (SerialButtonsValue1 & 16) != 0 || testButtonStateB == 0)
                  {
                      //B Button
                      Reply[3] &= ~0x40;//B
                  }
                  
                  if ((SerialButtonsValue1 & 2) != 0 || (SerialButtonsValue1 & 4) != 0 || (SerialButtonsValue1 & 32) != 0 || testButtonStateA == 0)
                  {
                      //A Button
                      Reply[2] &= ~0x08;//A
                  }

                  if ((SerialButtonsValue1 & 1) != 0 || testButtonStateTrigger == 0)
                  {
                      //Trigger
                      Reply[3] &= ~0x20;//Trigger
                  }
                }
      }
  }
}



