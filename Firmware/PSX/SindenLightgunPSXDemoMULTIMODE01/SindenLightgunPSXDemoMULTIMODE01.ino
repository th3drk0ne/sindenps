//This Arduino code sample is shared under 
//Creative Commons Attribution-NonCommercial 3.0 Unported license

// Based on Charlie Cole's LightGunVerter project
// Modified for Sinden Lightgun PS1 interface with PAL/NTSC toggle + trigger pulse feedback

#include <SPI.h>
#include <EEPROM.h>

// -----------------------------
// PS1 PIN DEFINITIONS
// -----------------------------
#define IN_CMD   MOSI
#define OUT_DATA MISO
#define OUT_ACK  7
#define IN_ATT   SS
#define IN_CLK   SCK

#define TestButtonTrigger 5
#define TestButtonA 4
#define TestButtonB 3

#define CONTROLLER_DATA_SIZE 8
#define DATA_SIZE 8

uint8_t ReadMask[DATA_SIZE]   = { 0xFF, 0xFF, 0, 0, 0, 0, 0, 0 };
uint8_t ReadExpect[DATA_SIZE] = { 0x01, 0x42, 0, 0, 0, 0, 0, 0 };
uint8_t Reply[DATA_SIZE]      = { 0x63, 0x5A, 0xFF, 0xFF, 0x01, 0x00, 0x05, 0x00 };

uint8_t DataIndex = 0;
bool bDataGood = true;

// -----------------------------
// REGION MODE
// -----------------------------
bool isPAL = true;  // default PAL unless EEPROM says otherwise

// PAL ranges
const int PAL_X_MIN = 77;
const int PAL_X_MAX = 461;
const int PAL_Y_MIN = 32;
const int PAL_Y_MAX = 295;

// NTSC ranges
const int NTSC_X_MIN = 77;
const int NTSC_X_MAX = 440;
const int NTSC_Y_MIN = 25;
const int NTSC_Y_MAX = 248;

// -----------------------------
// BUTTON STATE
// -----------------------------
int testButtonStateTrigger = 0;
int testButtonStateA = 0;
int testButtonStateB = 0;

// -----------------------------
// HOLD-TO-SWITCH TIMERS
// -----------------------------
unsigned long holdStartPAL = 0;
unsigned long holdStartNTSC = 0;
const unsigned long holdTime = 2000; // 2 seconds

// -----------------------------
// TRIGGER PULSE FEEDBACK
// -----------------------------
void pulseTrigger(int count) {
  for (int i = 0; i < count; i++) {
    Reply[3] &= ~0x20;  // Trigger ON
    delay(60);
    Reply[3] |= 0x20;   // Trigger OFF
    delay(60);
  }
}

// -----------------------------
// MACROS
// -----------------------------
#define ReadAttention() (PINB&(1<<2))
#define WriteAckLow() (DDRD|=(1<<7))
#define WriteAckHigh() (DDRD&=~(1<<7))
#define DelayMicro() asm("NOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\n")

inline int ReadCommand() { return digitalRead(IN_CMD); }

// -----------------------------
// EEPROM LOAD/SAVE
// -----------------------------
void loadRegion() {
  uint8_t val = EEPROM.read(0);
  isPAL = (val == 1);
}

void saveRegion() {
  EEPROM.write(0, isPAL ? 1 : 0);
}

// -----------------------------
// SETUP
// -----------------------------
void setup() {
  pinMode(OUT_ACK, INPUT);
  digitalWrite(OUT_ACK, 0);

  pinMode(MISO, OUTPUT);
  SPCR |= bit(SPE)|bit(DORD)|bit(CPOL)|bit(CPHA);
  SPI.attachInterrupt();

  pinMode(TestButtonTrigger, INPUT_PULLUP);
  pinMode(TestButtonA, INPUT_PULLUP);
  pinMode(TestButtonB, INPUT_PULLUP);

  Serial.begin(57600);
  while (!Serial) {}

  loadRegion();
}

// -----------------------------
// SPI INTERRUPT
// -----------------------------
ISR (SPI_STC_vect)
{
  uint8_t DataIn = SPDR;

  if (DataIndex < DATA_SIZE)
  {
    bDataGood &= ((DataIn & ReadMask[DataIndex]) == ReadExpect[DataIndex]);

    if (bDataGood)
    {
      SPDR = Reply[DataIndex];

      WriteAckLow();
      DelayMicro(); DelayMicro(); DelayMicro(); DelayMicro();
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

// -----------------------------
// MAIN LOOP
// -----------------------------
void loop()
{
  if (ReadAttention() != 0)
  {
    if (DataIndex != 0)
    {
      DataIndex = 0;
      bDataGood = true;
    }

    // Test buttons
    testButtonStateTrigger = digitalRead(TestButtonTrigger);
    testButtonStateA = digitalRead(TestButtonA);
    testButtonStateB = digitalRead(TestButtonB);

    // -----------------------------
    // HOLD-TO-SWITCH REGION MODE
    // Trigger + A = PAL (4 pulses)
    // Trigger + B = NTSC (2 pulses)
    // -----------------------------

    // PAL
    if (testButtonStateTrigger == 0 && testButtonStateA == 0) {
      if (holdStartPAL == 0) holdStartPAL = millis();
      if (millis() - holdStartPAL > holdTime) {
        isPAL = true;
        saveRegion();
        pulseTrigger(4);   // PAL confirmation
        holdStartPAL = 0;
      }
    } else {
      holdStartPAL = 0;
    }

    // NTSC
    if (testButtonStateTrigger == 0 && testButtonStateB == 0) {
      if (holdStartNTSC == 0) holdStartNTSC = millis();
      if (millis() - holdStartNTSC > holdTime) {
        isPAL = false;
        saveRegion();
        pulseTrigger(2);   // NTSC confirmation
        holdStartNTSC = 0;
      }
    } else {
      holdStartNTSC = 0;
    }

    // -----------------------------
    // SERIAL INPUT FROM SINDEN
    // -----------------------------
    if (Serial.available() > 5)
    {
      int StartByte = Serial.read();
      int SerialX = Serial.read();
      int SerialY = Serial.read();
      int SerialButtonsValue1 = Serial.read();
      int SerialButtonsValue2 = Serial.read();
      int EndByte = Serial.read();

      if (StartByte != 222 || EndByte != 223)
      {
        int LookingForEnd = 0;
        while (LookingForEnd != 223)
        {
          if (Serial.available() > 0)
            LookingForEnd = Serial.read();
        }
      }
      else
      {
        // -----------------------------
        // OFFSCREEN CHECK
        // -----------------------------
        if (SerialX < 3 || SerialX > 252 || SerialY < 3 || SerialY > 252)
        {
          Reply[4] = 0x01;
          Reply[5] = 0x00;
          Reply[6] = 0x05;
          Reply[7] = 0x00;
        }
        else
        {
          float percentx = SerialX / 255.0;
          float percenty = SerialY / 255.0;

          int xmin = isPAL ? PAL_X_MIN : NTSC_X_MIN;
          int xmax = isPAL ? PAL_X_MAX : NTSC_X_MAX;
          int ymin = isPAL ? PAL_Y_MIN : NTSC_Y_MIN;
          int ymax = isPAL ? PAL_Y_MAX : NTSC_Y_MAX;

          float positionx = percentx * (xmax - xmin) + xmin;
          float positiony = percenty * (ymax - ymin) + ymin;

          int posx = (int)positionx;
          int posy = (int)positiony;

          Reply[4] = (posx > 255) ? posx - 255 : posx;
          Reply[5] = (posx > 255) ? 0x01 : 0x00;

          Reply[6] = (posy > 255) ? posy - 255 : posy;
          Reply[7] = (posy > 255) ? 0x01 : 0x00;
        }

        // -----------------------------
        // BUTTONS
        // -----------------------------
        Reply[2] = 0xFF;
        Reply[3] = 0xFF;

        if ((SerialButtonsValue1 & 8) || (SerialButtonsValue1 & 16) || testButtonStateB == 0)
          Reply[3] &= ~0x40;

        if ((SerialButtonsValue1 & 2) || (SerialButtonsValue1 & 4) || (SerialButtonsValue1 & 32) || testButtonStateA == 0)
          Reply[2] &= ~0x08;

        if ((SerialButtonsValue1 & 1) || testButtonStateTrigger == 0)
          Reply[3] &= ~0x20;
      }
    }
  }
}
