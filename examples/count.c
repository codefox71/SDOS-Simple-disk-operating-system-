//basic program test for jumps
int main(){
    int a = 0;
    int count = 0xfffa;
    while(count){
        a = a + 1;
        count = count + 1;
        putchar(a);
    }
}